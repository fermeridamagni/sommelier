import Foundation

/// Errors that can occur during subprocess execution.
enum ProcessError: Error, LocalizedError, Sendable {
    /// The process failed to launch (e.g. permission denied, invalid binary format).
    case executionFailed(String)

    /// The process exited with a non-zero status code.
    case nonZeroExit(code: Int32, stderr: String)

    /// The executable was not found at the specified path.
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .executionFailed(let message):
            "Process execution failed: \(message)"
        case .nonZeroExit(let code, let stderr):
            "Process exited with code \(code): \(stderr)"
        case .notFound(let path):
            "Executable not found: \(path)"
        }
    }
}

/// The captured output and exit status of a completed subprocess.
struct ProcessResult: Sendable {
    /// The process's exit code (0 typically means success).
    let exitCode: Int32

    /// All text written to standard output, concatenated.
    let stdout: String

    /// All text written to standard error, concatenated.
    let stderr: String
}

/// An actor that wraps `Foundation.Process` for safe, async subprocess execution.
///
/// Uses `Pipe` for stdout/stderr capture and reads both streams concurrently
/// in a `TaskGroup` to prevent pipe buffer deadlocks — a classic pitfall where
/// a full pipe blocks the child process, which in turn never closes the other
/// pipe, causing a deadlock.
///
/// All methods are isolated to this actor, ensuring thread-safe access to any
/// shared state and preventing concurrent mutation issues.
actor ProcessRunner {
    /// Shared singleton instance for convenience.
    ///
    /// Services that need testability should accept `ProcessRunner` as an
    /// injected dependency rather than using this singleton.
    static let shared = ProcessRunner()

    /// Runs an executable with the given arguments and optional environment.
    ///
    /// - Parameters:
    ///   - executablePath: Absolute path to the executable binary.
    ///   - arguments: Command-line arguments to pass.
    ///   - environment: Custom environment variables. Merged with the
    ///     current process's environment so PATH and other essentials are preserved.
    ///   - workingDirectory: Optional working directory for the child process.
    ///   - onStdout: Optional closure called for each line written to stdout.
    ///     Useful for streaming progress output to the UI.
    ///   - onStderr: Optional closure called for each line written to stderr.
    /// - Returns: A `ProcessResult` with the exit code and captured output.
    /// - Throws: `ProcessError` if the executable is missing or fails to launch.
    func run(
        executablePath: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: String? = nil,
        stdinPipe: Pipe? = nil,
        onStdout: (@Sendable (String) -> Void)? = nil,
        onStderr: (@Sendable (String) -> Void)? = nil
    ) async throws -> ProcessResult {
        // Verify the executable exists before attempting to launch.
        guard FileManager.default.fileExists(atPath: executablePath) else {
            throw ProcessError.notFound(executablePath)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        // Merge custom env vars with the current process environment so
        // PATH, HOME, and other essentials are preserved.
        if let environment {
            var merged = ProcessInfo.processInfo.environment
            for (key, value) in environment {
                merged[key] = value
            }
            process.environment = merged
        }

        if let workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        if let stdinPipe {
            process.standardInput = stdinPipe
        }

        // Bridge the callback-based Process.terminationHandler to async/await.
        return try await withCheckedThrowingContinuation { continuation in
            // Read stdout and stderr concurrently in a detached task to avoid
            // pipe buffer deadlocks. Both streams must be drained simultaneously.
            let readTask = Task.detached { [stdoutPipe, stderrPipe] () -> (String, String) in
                async let stdoutResult: String = {
                    var fullOutput = ""
                    var currentLine = ""
                    do {
                        for try await byte in stdoutPipe.fileHandleForReading.bytes {
                            let char = Character(UnicodeScalar(byte))
                            currentLine.append(char)
                            fullOutput.append(char)
                            
                            if char == "\n" {
                                onStdout?(currentLine)
                                currentLine = ""
                            } else if currentLine.hasSuffix(": ") || currentLine.hasSuffix("? ") || currentLine.hasSuffix("> ") {
                                onStdout?(currentLine)
                                currentLine = ""
                            }
                        }
                    } catch {
                        // Task cancelled or pipe closed
                    }
                    if !currentLine.isEmpty {
                        onStdout?(currentLine)
                    }
                    return fullOutput
                }()

                async let stderrResult: String = {
                    var fullOutput = ""
                    var currentLine = ""
                    do {
                        for try await byte in stderrPipe.fileHandleForReading.bytes {
                            let char = Character(UnicodeScalar(byte))
                            currentLine.append(char)
                            fullOutput.append(char)
                            
                            if char == "\n" {
                                onStderr?(currentLine)
                                currentLine = ""
                            } else if currentLine.hasSuffix(": ") || currentLine.hasSuffix("? ") || currentLine.hasSuffix("> ") {
                                onStderr?(currentLine)
                                currentLine = ""
                            }
                        }
                    } catch {
                        // Task cancelled or pipe closed
                    }
                    if !currentLine.isEmpty {
                        onStderr?(currentLine)
                    }
                    return fullOutput
                }()

                // Await both concurrently
                let stdout = await stdoutResult
                let stderr = await stderrResult
                return (stdout, stderr)
            }

            process.terminationHandler = { terminatedProcess in
                // Allow read loops to finish naturally to ensure we don't truncate
                // output (like large JSON payloads) that are still buffered in the pipe.
                // However, some CLI tools (like Python multiprocessing) spawn child processes
                // that inherit the pipes and keep them open. We use a 500ms timeout to gracefully
                // let the buffer drain, and then cancel the read task to prevent hanging.
                Task {
                    let timeoutTask = Task {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        readTask.cancel()
                    }
                    
                    let (stdout, stderr) = await readTask.value
                    timeoutTask.cancel()
                    
                    let result = ProcessResult(
                        exitCode: terminatedProcess.terminationStatus,
                        stdout: stdout,
                        stderr: stderr
                    )
                    continuation.resume(returning: result)
                }
            }

            do {
                try process.run()
            } catch {
                readTask.cancel()
                continuation.resume(
                    throwing: ProcessError.executionFailed(error.localizedDescription)
                )
            }
        }
    }

    /// Convenience method that locates a command by name and runs it.
    ///
    /// Searches common binary directories (`/usr/bin`, `/usr/local/bin`,
    /// `/opt/homebrew/bin`) for the executable.
    ///
    /// - Parameters:
    ///   - command: The name of the command (e.g. `"legendary"`).
    ///   - arguments: Arguments to pass to the command.
    /// - Returns: A `ProcessResult` with captured output.
    /// - Throws: `ProcessError.notFound` if the command isn't in any search path.
    func run(
        command: String,
        arguments: [String] = [],
        stdinPipe: Pipe? = nil,
        onStdout: (@Sendable (String) -> Void)? = nil
    ) async throws -> ProcessResult {
        // Check Sommelier's internal bin directory first, which also falls back to `which`.
        if let path = await SystemInfoService.shared.findExecutable(command) {
            return try await run(executablePath: path, arguments: arguments, stdinPipe: stdinPipe, onStdout: onStdout)
        }

        // Fallback: check common Homebrew and system paths.
        let searchPaths = [
            "/opt/homebrew/bin/\(command)",
            "/usr/local/bin/\(command)",
            "/usr/bin/\(command)",
        ]

        for candidatePath in searchPaths {
            if FileManager.default.fileExists(atPath: candidatePath) {
                return try await run(executablePath: candidatePath, arguments: arguments, stdinPipe: stdinPipe, onStdout: onStdout)
            }
        }

        throw ProcessError.notFound(command)
    }

    /// Runs an arbitrary shell command string via `/bin/zsh -c`.
    ///
    /// Suitable for one-liners and piped commands. For structured invocations,
    /// prefer `run(executablePath:arguments:)` to avoid shell injection risks.
    ///
    /// - Parameter command: The shell command to execute (e.g. `"ls -la | head"`).
    /// - Returns: A `ProcessResult` with captured output.
    /// - Throws: `ProcessError` on execution failure.
    func runShell(_ command: String) async throws -> ProcessResult {
        try await run(
            executablePath: "/bin/zsh",
            arguments: ["-c", command]
        )
    }
}
