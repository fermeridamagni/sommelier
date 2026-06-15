import Foundation

/// Errors that can occur during Wine/GPTK bottle management.
enum WineError: Error, LocalizedError, Sendable {
    /// GPTK's `wine64` binary was not found in Sommelier's internal directory.
    case gptkNotFound

    /// The bottle directory could not be created on disk.
    case bottleCreationFailed(String)

    /// The `wineboot` initialization command failed.
    case winebootFailed(String)

    /// Failed to launch a game executable through Wine.
    case launchFailed(String)

    /// The specified bottle directory does not exist.
    case bottleNotFound(String)

    /// Failed to delete a bottle's directory from disk.
    case deletionFailed(String)

    var errorDescription: String? {
        switch self {
        case .gptkNotFound:
            "Game Porting Toolkit (wine64) was not found. Install it via the Onboarding wizard by dragging Apple's GPTK DMG."
        case .bottleCreationFailed(let reason):
            "Failed to create Wine bottle: \(reason)"
        case .winebootFailed(let reason):
            "Wine initialization failed: \(reason)"
        case .launchFailed(let reason):
            "Failed to launch game: \(reason)"
        case .bottleNotFound(let path):
            "Wine bottle not found at: \(path)"
        case .deletionFailed(let reason):
            "Failed to delete bottle: \(reason)"
        }
    }
}

/// Manages Wine/GPTK bottles — creating, launching games within, and deleting them.
///
/// A "bottle" is a WINEPREFIX directory containing an isolated Windows environment
/// (registry, `drive_c/`, etc.). This actor coordinates `wine64` invocations through
/// `ProcessRunner` and ensures operations are serialized to prevent concurrent
/// modifications to the same bottle.
actor WineManager {
    /// Shared singleton instance.
    static let shared = WineManager()

    /// The process runner used for all Wine subprocess invocations.
    private let processRunner: ProcessRunner

    /// The system info service for locating GPTK binaries.
    private let systemInfo: SystemInfoService

    /// Base directory where all bottles are stored.
    ///
    /// Defaults to `~/Library/Application Support/Sommelier/Bottles/`.
    let bottlesDirectory: URL

    /// Tracks running game process IDs so they can be terminated later.
    ///
    /// Key: game UUID, Value: the `Process` instance.
    private var runningProcesses: [UUID: Process] = [:]

    /// Creates a new `WineManager`.
    ///
    /// - Parameters:
    ///   - processRunner: The process runner for subprocess execution.
    ///   - systemInfo: System info service for GPTK detection.
    ///   - bottlesDirectory: Override for the bottles storage directory.
    init(
        processRunner: ProcessRunner = .shared,
        systemInfo: SystemInfoService = .shared,
        bottlesDirectory: URL? = nil
    ) {
        self.processRunner = processRunner
        self.systemInfo = systemInfo

        if let bottlesDirectory {
            self.bottlesDirectory = bottlesDirectory
        } else {
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
            self.bottlesDirectory = appSupport
                .appendingPathComponent("Sommelier", isDirectory: true)
                .appendingPathComponent("Bottles", isDirectory: true)
        }
    }

    /// Creates a new Wine bottle and initializes it with `wineboot`.
    ///
    /// Steps:
    /// 1. Locate the GPTK `wine64` binary from Sommelier's internal GPTK directory
    /// 2. Create a unique directory under `bottlesDirectory`
    /// 3. Run `wine64 wineboot -i` with `WINEPREFIX` set to initialize
    ///    the Windows filesystem, registry, and core DLLs
    /// 4. Return a configured `Bottle` model for persistence
    ///
    /// - Parameters:
    ///   - name: A human-readable name for the bottle.
    ///   - game: Optional game to associate this bottle with.
    /// - Returns: A fully initialized `Bottle` model.
    /// - Throws: `WineError.gptkNotFound` if GPTK isn't installed,
    ///   `WineError.bottleCreationFailed` or `WineError.winebootFailed`
    ///   if initialization fails.
    func createBottle(name: String, gameID: UUID? = nil) async throws -> (id: UUID, path: String, wineBinaryPath: String) {
        // Step 1: Locate wine64.
        guard let wine64Path = await systemInfo.gptkBinaryPath() else {
            throw WineError.gptkNotFound
        }

        // Step 2: Create a directory for this bottle.
        let bottleID = UUID()
        let bottlePath = bottlesDirectory.appendingPathComponent(bottleID.uuidString)

        do {
            try FileManager.default.createDirectory(
                at: bottlePath,
                withIntermediateDirectories: true
            )
        } catch {
            throw WineError.bottleCreationFailed(error.localizedDescription)
        }

        // Step 3: Initialize the bottle with wineboot.
        let environment = [
            "WINEPREFIX": bottlePath.path,
        ]

        let result = try await processRunner.run(
            executablePath: wine64Path,
            arguments: ["wineboot", "-i"],
            environment: environment
        )

        if result.exitCode != 0 {
            // Clean up the failed bottle directory.
            try? FileManager.default.removeItem(at: bottlePath)
            throw WineError.winebootFailed(result.stderr)
        }

        // Step 4: Return the configured model parameters.
        return (bottleID, bottlePath.path, wine64Path)
    }

    /// Launches a game executable inside a Wine bottle.
    ///
    /// Builds the environment variables dictionary (WINEPREFIX, WINEESYNC,
    /// MTL_HUD_ENABLED, etc.) from the bottle configuration and user settings,
    /// then spawns `wine64 <exe_path>`.
    ///
    /// - Parameters:
    ///   - gameID: The UUID of the game.
    ///   - executablePath: The game executable path.
    ///   - installPath: The game install path.
    ///   - bottlePath: The Wine bottle path.
    ///   - wineBinaryPath: The Wine binary path.
    ///   - environmentVariables: The bottle environment variables.
    ///   - onExit: Closure called when the process terminates, returning elapsed time.
    /// - Throws: `WineError.launchFailed` if the Wine process fails to start.
    func launch(
        gameID: UUID,
        executablePath: String,
        installPath: String?,
        bottlePath: String,
        wineBinaryPath: String,
        environmentVariables: [String: String],
        onExit: @escaping @Sendable (TimeInterval) -> Void
    ) async throws {
        let settings = AppSettings.load()
        let environment = gptkEnvironment(bottlePath: bottlePath, envVars: environmentVariables, settings: settings)

        // Spawn wine64 with the game's executable path.
        // We track the process so it can be terminated later.
        guard FileManager.default.fileExists(atPath: wineBinaryPath) else {
            throw WineError.gptkNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: wineBinaryPath)
        process.arguments = [executablePath]

        var merged = ProcessInfo.processInfo.environment
        for (key, value) in environment {
            merged[key] = value
        }
        process.environment = merged

        // Set working directory to the game's install path if available.
        if let installPath = installPath {
            process.currentDirectoryURL = URL(fileURLWithPath: installPath)
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let startTime = Date()
        process.terminationHandler = { [weak self] _ in
            let elapsed = Date().timeIntervalSince(startTime)
            Task {
                await self?.removeProcess(gameID: gameID)
                onExit(elapsed)
            }
        }

        do {
            try process.run()
            runningProcesses[gameID] = process
        } catch {
            throw WineError.launchFailed(error.localizedDescription)
        }
    }

    private func removeProcess(gameID: UUID) {
        runningProcesses.removeValue(forKey: gameID)
    }

    /// Terminates a running game process by its game ID.
    ///
    /// Sends `SIGTERM` to the Wine process. If the process doesn't
    /// exist or has already exited, this is a no-op.
    ///
    /// - Parameter gameID: The UUID of the game whose process should be terminated.
    func terminate(gameID: UUID) async throws {
        guard let process = runningProcesses[gameID] else { return }

        if process.isRunning {
            process.terminate()
        }
        runningProcesses.removeValue(forKey: gameID)
    }

    /// Deletes a Wine bottle's directory and all its contents from disk.
    ///
    /// ⚠️ This is destructive and irreversible — the entire WINEPREFIX
    /// including any installed games, save data, and registry settings
    /// will be permanently removed.
    ///
    /// - Parameter bottlePath: The path to the bottle.
    /// - Throws: `WineError.bottleNotFound` if the directory doesn't exist,
    ///   `WineError.deletionFailed` if removal fails.
    func deleteBottle(atPath bottlePath: String) async throws {
        let bottleURL = URL(fileURLWithPath: bottlePath)

        guard FileManager.default.fileExists(atPath: bottlePath) else {
            throw WineError.bottleNotFound(bottlePath)
        }

        do {
            try FileManager.default.removeItem(at: bottleURL)
        } catch {
            throw WineError.deletionFailed(error.localizedDescription)
        }
    }

    /// Builds the complete environment variable dictionary for a GPTK session.
    ///
    /// Merges the bottle's custom variables with standard GPTK/Wine settings
    /// derived from the user's `AppSettings`.
    ///
    /// - Parameters:
    ///   - bottlePath: The WINEPREFIX path.
    ///   - envVars: Custom variables.
    ///   - settings: The user's app settings for runtime toggles.
    /// - Returns: A dictionary of environment variables ready for `Process.environment`.
    func gptkEnvironment(bottlePath: String, envVars: [String: String], settings: AppSettings) -> [String: String] {
        var env: [String: String] = [
            // The Wine prefix directory — the most important variable.
            "WINEPREFIX": bottlePath,
        ]

        // Enable esync for better threading performance (default on).
        if settings.enableEsync {
            env["WINEESYNC"] = "1"
        }

        // Enable Metal performance HUD overlay.
        if settings.enableMetalHUD {
            env["MTL_HUD_ENABLED"] = "1"
        }

        // Merge bottle-specific custom environment variables.
        // These take precedence over the standard ones so users
        // can override any setting per-bottle.
        for (key, value) in envVars {
            env[key] = value
        }

        return env
    }
}
