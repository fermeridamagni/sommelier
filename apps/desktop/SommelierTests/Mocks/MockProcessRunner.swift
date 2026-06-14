import Foundation
@testable import Sommelier

/// A testable mock of `ProcessRunner` that returns canned responses.
///
/// Instead of spawning real child processes, this mock returns
/// pre-configured `ProcessResult` values keyed by executable path
/// or command name. Tests use this to verify that services correctly
/// parse CLI output without depending on actual CLI tools.
actor MockProcessRunner {
    /// Canned results keyed by command/executable name.
    var results: [String: ProcessResult] = [:]

    /// Records of commands that were invoked, for assertion purposes.
    var invocations: [(command: String, arguments: [String])] = []

    /// Registers a canned result for a given command name.
    func setResult(for command: String, result: ProcessResult) {
        results[command] = result
    }

    /// Simulates running a command by name.
    func run(
        command: String,
        arguments: [String] = [],
        stdinPipe: Pipe? = nil,
        onStdout: (@Sendable (String) -> Void)? = nil
    ) async throws -> ProcessResult {
        invocations.append((command: command, arguments: arguments))

        if let result = results[command] {
            return result
        }

        // Default: return empty success
        return ProcessResult(exitCode: 0, stdout: "", stderr: "")
    }

    /// Simulates running an executable by path.
    func run(
        executablePath: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: String? = nil,
        stdinPipe: Pipe? = nil,
        onStdout: (@Sendable (String) -> Void)? = nil,
        onStderr: (@Sendable (String) -> Void)? = nil
    ) async throws -> ProcessResult {
        let name = URL(fileURLWithPath: executablePath).lastPathComponent
        invocations.append((command: name, arguments: arguments))

        if let result = results[name] {
            return result
        }

        return ProcessResult(exitCode: 0, stdout: "", stderr: "")
    }
}
