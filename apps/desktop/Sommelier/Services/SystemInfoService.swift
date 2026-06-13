import Foundation
import SwiftUI

/// Represents the installation state of a system dependency.
enum DependencyStatus: Sendable, Equatable {
    /// The dependency status is being checked.
    case checking

    /// The dependency is installed and available.
    case installed

    /// The dependency is not installed.
    case notInstalled

    /// The dependency is currently being installed.
    case installing

    /// An error occurred while checking or installing the dependency.
    case error(String)

    /// Whether this dependency is in a resolved (non-pending) state.
    var isResolved: Bool {
        switch self {
        case .installed, .notInstalled, .error: true
        default: false
        }
    }

    /// Display-friendly label for the current status.
    var label: String {
        switch self {
        case .checking: "Checking…"
        case .installed: "Installed"
        case .notInstalled: "Not Installed"
        case .installing: "Installing…"
        case .error(let msg): "Error: \(msg)"
        }
    }

    /// Color representing this status for SwiftUI views.
    var color: Color {
        switch self {
        case .checking: .secondary
        case .installed: .green
        case .notInstalled: .orange
        case .installing: .blue
        case .error: .red
        }
    }
}

/// Provides system information and dependency detection for Sommelier.
///
/// This service detects whether the Mac has Apple Silicon, Rosetta 2,
/// Homebrew, and GPTK installed — all prerequisites for running Windows
/// games via the Game Porting Toolkit. It's a `final class` (not an actor)
/// because most properties are computed on-demand or delegate to
/// `ProcessRunner`, which is already thread-safe.
final class SystemInfoService: Sendable {
    /// Shared singleton instance.
    static let shared = SystemInfoService()

    /// The process runner used for executing shell commands.
    private let processRunner: ProcessRunner

    /// Creates a new `SystemInfoService` with the given process runner.
    ///
    /// - Parameter processRunner: The runner to use for subprocess execution.
    ///   Defaults to the shared singleton.
    init(processRunner: ProcessRunner = .shared) {
        self.processRunner = processRunner
    }

    // MARK: - Architecture Detection

    /// Whether this Mac has an Apple Silicon (ARM64) processor.
    ///
    /// Uses a compile-time check first, then falls back to `sysctlbyname`
    /// at runtime so the property works correctly even if the binary is
    /// running under Rosetta translation.
    var isAppleSilicon: Bool {
        #if arch(arm64)
        return true
        #else
        // Runtime fallback: check the hw.optional.arm64 sysctl.
        // This handles the case where a universal binary runs its x86_64
        // slice under Rosetta on Apple Silicon hardware.
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname("hw.optional.arm64", &value, &size, nil, 0)
        return result == 0 && value == 1
        #endif
    }

    // MARK: - Rosetta

    /// Whether Rosetta 2 is installed on this system.
    ///
    /// Rosetta is required for running x86_64 Wine binaries on Apple Silicon.
    /// Checks for the existence of the Rosetta runtime library — the canonical
    /// way to detect Rosetta without spawning a process.
    func isRosettaInstalled() -> Bool {
        FileManager.default.fileExists(
            atPath: "/Library/Apple/usr/libexec/oah/libRosettaRuntime"
        )
    }

    /// Installs Rosetta 2 using Apple's `softwareupdate` command.
    ///
    /// This requires admin privileges on first run but `--agree-to-license`
    /// avoids the interactive license prompt. The function waits for
    /// installation to complete.
    ///
    /// - Throws: `ProcessError` if the installation command fails.
    func installRosetta() async throws {
        let result = try await processRunner.run(
            executablePath: "/usr/sbin/softwareupdate",
            arguments: ["--install-rosetta", "--agree-to-license"]
        )
        if result.exitCode != 0 {
            throw ProcessError.nonZeroExit(code: result.exitCode, stderr: result.stderr)
        }
    }

    // MARK: - GPTK

    /// The internal GPTK directory managed by Sommelier.
    ///
    /// GPTK binaries are extracted from Apple's official DMG into
    /// `~/Library/Application Support/Sommelier/GPTK/` during onboarding.
    /// This eliminates the Homebrew dependency entirely.
    static let gptkDirectory: URL = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport
            .appendingPathComponent("Sommelier", isDirectory: true)
            .appendingPathComponent("GPTK", isDirectory: true)
    }()

    /// Locates the GPTK `wine64` binary in Sommelier's internal directory.
    ///
    /// Checks `~/Library/Application Support/Sommelier/GPTK/bin/wine64`,
    /// which is extracted from Apple's official GPTK 3.0 DMG during the
    /// onboarding flow. Returns `nil` if GPTK hasn't been installed yet.
    ///
    /// - Returns: Absolute path to the `wine64` binary, or `nil`.
    func gptkBinaryPath() async -> String? {
        let wine64Path = Self.gptkDirectory
            .appendingPathComponent("bin")
            .appendingPathComponent("wine64")
            .path

        return FileManager.default.fileExists(atPath: wine64Path) ? wine64Path : nil
    }

    /// Whether GPTK is installed in Sommelier's internal directory.
    ///
    /// Synchronous convenience for UI status checks — avoids spawning
    /// a process just to verify the binary exists on disk.
    func isGPTKInstalled() -> Bool {
        let wine64Path = Self.gptkDirectory
            .appendingPathComponent("bin")
            .appendingPathComponent("wine64")
            .path
        return FileManager.default.fileExists(atPath: wine64Path)
    }

    /// The internal bin directory where Sommelier installs CLI tools.
    static let binDirectory: URL = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport
            .appendingPathComponent("Sommelier", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
    }()

    // MARK: - Generic Executable Detection

    /// Locates a CLI executable by name.
    ///
    /// Checks Sommelier's internal `bin/` directory first, then falls back to the system PATH.
    ///
    /// - Parameter name: The executable name (e.g. `"legendary"`, `"nile"`).
    /// - Returns: The absolute path to the executable, or `nil` if not found.
    func findExecutable(_ name: String) async -> String? {
        let fm = FileManager.default
        
        // 1. Check internal bin directory
        var internalPath = Self.binDirectory.appendingPathComponent(name).path
        if name == "steamcmd" {
            // SteamCMD is wrapped in a shell script inside a subfolder
            internalPath = Self.binDirectory
                .appendingPathComponent("steamcmd")
                .appendingPathComponent("steamcmd.sh").path
        }
        
        if fm.fileExists(atPath: internalPath) {
            return internalPath
        }

        // 2. Fallback to system PATH
        guard let result = try? await processRunner.runShell("which \(name)") else {
            return nil
        }
        let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, result.exitCode == 0 else { return nil }
        return path
    }

    /// Checks whether a named dependency is installed and available.
    ///
    /// This is a high-level check that returns a `DependencyStatus` suitable
    /// for driving UI indicators (e.g. checkmarks in the onboarding flow).
    ///
    /// - Parameter name: The dependency to check. Recognized names:
    ///   `"rosetta"`, `"gptk"`, or any CLI tool name.
    /// - Returns: The current `DependencyStatus` for the dependency.
    func checkDependency(_ name: String) async -> DependencyStatus {
        switch name.lowercased() {
        case "rosetta":
            return isRosettaInstalled() ? .installed : .notInstalled

        case "gptk", "game-porting-toolkit":
            return isGPTKInstalled() ? .installed : .notInstalled

        default:
            // Treat as a generic CLI tool name.
            let path = await findExecutable(name)
            return path != nil ? .installed : .notInstalled
        }
    }
}
import Foundation

enum CLITool: String, CaseIterable, Identifiable {
    case legendary = "Legendary"
    case steamcmd = "SteamCMD"
    case nile = "Nile"
    
    var id: String { rawValue }
}

/// Errors that can occur during CLI installation.
enum CLIDownloadError: Error, LocalizedError {
    case downloadFailed(String)
    case extractionFailed(String)
    case fileSystemError(String)
    
    var errorDescription: String? {
        switch self {
        case .downloadFailed(let msg): return "Download failed: \(msg)"
        case .extractionFailed(let msg): return "Extraction failed: \(msg)"
        case .fileSystemError(let msg): return "File system error: \(msg)"
        }
    }
}

/// Manages the background download, extraction, and installation of third-party CLI tools.
final class CLIDownloadManager: Sendable {
    static let shared = CLIDownloadManager()
    
    private let processRunner: ProcessRunner
    
    init(processRunner: ProcessRunner = .shared) {
        self.processRunner = processRunner
    }
    
    /// Ensures the internal bin directory exists.
    private func ensureBinDirectory() throws {
        let fm = FileManager.default
        let binDir = SystemInfoService.binDirectory
        if !fm.fileExists(atPath: binDir.path) {
            try fm.createDirectory(at: binDir, withIntermediateDirectories: true)
        }
    }
    
    // MARK: - Generic Download Helper
    
    private func downloadFile(url: URL, to tempPath: URL, progressHandler: @escaping @Sendable (Double) -> Void) async throws {
        let result = try await processRunner.run(
            executablePath: "/usr/bin/curl",
            arguments: ["-L", "-#", url.absoluteString, "-o", tempPath.path],
            environment: nil,
            workingDirectory: nil,
            onStdout: nil,
            onStderr: { output in
                let pattern = "([0-9]+\\.[0-9]+)%"
                if let regex = try? NSRegularExpression(pattern: pattern),
                   let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)) {
                    if let range = Range(match.range(at: 1), in: output),
                       let percent = Double(String(output[range])) {
                        progressHandler(percent / 100.0)
                    }
                }
            }
        )
        
        guard result.exitCode == 0 else {
            throw CLIDownloadError.downloadFailed(result.stderr)
        }
    }
    
    // MARK: - Tool Installers
    
    func downloadLegendary(progress: @escaping @Sendable (Double) -> Void) async throws {
        try ensureBinDirectory()
        let fm = FileManager.default
        
        let urlStr = "https://github.com/legendary-gl/legendary/releases/latest/download/legendary_macOS.zip"
        guard let url = URL(string: urlStr) else { throw CLIDownloadError.downloadFailed("Invalid URL") }
        
        let tempZip = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + "_legendary.zip")
        let tempExtractDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        
        defer {
            try? fm.removeItem(at: tempZip)
            try? fm.removeItem(at: tempExtractDir)
        }
        
        // 1. Download
        try await downloadFile(url: url, to: tempZip, progressHandler: progress)
        
        // 2. Extract
        try fm.createDirectory(at: tempExtractDir, withIntermediateDirectories: true)
        let unzipResult = try await processRunner.run(
            executablePath: "/usr/bin/unzip",
            arguments: ["-q", tempZip.path, "-d", tempExtractDir.path]
        )
        guard unzipResult.exitCode == 0 else {
            throw CLIDownloadError.extractionFailed(unzipResult.stderr)
        }
        
        // 3. Move and make executable
        // Zip contains `legendary` directly or inside a folder.
        // The legendary_macOS.zip usually contains just `legendary` executable file.
        let extractedBinary = tempExtractDir.appendingPathComponent("legendary")
        guard fm.fileExists(atPath: extractedBinary.path) else {
            throw CLIDownloadError.extractionFailed("legendary binary not found in zip.")
        }
        
        let finalPath = SystemInfoService.binDirectory.appendingPathComponent("legendary")
        if fm.fileExists(atPath: finalPath.path) {
            try fm.removeItem(at: finalPath)
        }
        try fm.moveItem(at: extractedBinary, to: finalPath)
        
        let chmodResult = try await processRunner.run(executablePath: "/bin/chmod", arguments: ["+x", finalPath.path])
        guard chmodResult.exitCode == 0 else { throw CLIDownloadError.fileSystemError("chmod failed") }
    }
    
    func downloadNile(progress: @escaping @Sendable (Double) -> Void) async throws {
        try ensureBinDirectory()
        let fm = FileManager.default
        
        let isARM = SystemInfoService.shared.isAppleSilicon
        let archSuffix = isARM ? "arm64" : "x86_64"
        let urlStr = "https://github.com/imLinguin/nile/releases/latest/download/nile_macOS_\(archSuffix)"
        
        guard let url = URL(string: urlStr) else { throw CLIDownloadError.downloadFailed("Invalid URL") }
        
        let tempBin = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + "_nile")
        defer { try? fm.removeItem(at: tempBin) }
        
        // 1. Download directly
        try await downloadFile(url: url, to: tempBin, progressHandler: progress)
        
        // 2. Move
        let finalPath = SystemInfoService.binDirectory.appendingPathComponent("nile")
        if fm.fileExists(atPath: finalPath.path) {
            try fm.removeItem(at: finalPath)
        }
        try fm.moveItem(at: tempBin, to: finalPath)
        
        // 3. Make executable
        let chmodResult = try await processRunner.run(executablePath: "/bin/chmod", arguments: ["+x", finalPath.path])
        guard chmodResult.exitCode == 0 else { throw CLIDownloadError.fileSystemError("chmod failed") }
    }
    
    func downloadSteamCMD(progress: @escaping @Sendable (Double) -> Void) async throws {
        try ensureBinDirectory()
        let fm = FileManager.default
        
        let urlStr = "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_osx.tar.gz"
        guard let url = URL(string: urlStr) else { throw CLIDownloadError.downloadFailed("Invalid URL") }
        
        let tempTar = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + "_steamcmd.tar.gz")
        let extractDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + "_steamcmd")
        
        defer {
            try? fm.removeItem(at: tempTar)
            try? fm.removeItem(at: extractDir)
        }
        
        // 1. Download
        try await downloadFile(url: url, to: tempTar, progressHandler: progress)
        
        // 2. Extract
        try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)
        let untarResult = try await processRunner.run(
            executablePath: "/usr/bin/tar",
            arguments: ["-xzf", tempTar.path, "-C", extractDir.path]
        )
        guard untarResult.exitCode == 0 else {
            throw CLIDownloadError.extractionFailed(untarResult.stderr)
        }
        
        // 3. Move folder to bin/steamcmd
        let finalPath = SystemInfoService.binDirectory.appendingPathComponent("steamcmd")
        if fm.fileExists(atPath: finalPath.path) {
            try fm.removeItem(at: finalPath)
        }
        try fm.moveItem(at: extractDir, to: finalPath)
    }
}
