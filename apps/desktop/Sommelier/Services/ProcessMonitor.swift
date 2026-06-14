import AppKit
import Foundation

/// Monitors running game processes and reports lifecycle events.
///
/// Supports two monitoring modes:
/// - **Native macOS apps**: Observes `NSWorkspace` termination notifications.
/// - **Child processes**: Watches `Foundation.Process` termination handlers.
///
/// Used by `GameDetailViewModel` to update game status when a launched
/// game exits, and to track play time.
@MainActor
@Observable
final class ProcessMonitor {
    /// Shared singleton instance.
    static let shared = ProcessMonitor()

    /// Maps game IDs to their running native app instances for stop/status tracking.
    private var runningApps: [UUID: NSRunningApplication] = [:]

    /// Maps game IDs to their running child processes for stop/status tracking.
    private var runningProcesses: [UUID: Process] = [:]

    /// Maps game IDs to their launch timestamps for play time calculation.
    private var launchTimestamps: [UUID: Date] = [:]

    /// Maps game IDs to their specific exit handlers.
    private var exitHandlers: [UUID: @MainActor (TimeInterval) -> Void] = [:]

    /// Notification observer token for workspace app termination.
    /// Not removed in deinit because ProcessMonitor is a singleton
    /// that lives for the entire app lifecycle.
    private var terminationObserver: NSObjectProtocol?

    init() {
        setupWorkspaceObserver()
    }

    // MARK: - Workspace Observer

    /// Subscribes to `NSWorkspace.didTerminateApplicationNotification` to detect
    /// when native macOS apps launched by Sommelier exit.
    private func setupWorkspaceObserver() {
        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }

            Task { @MainActor in
                self?.handleNativeAppTermination(app)
            }
        }
    }

    /// Handles the termination of a native macOS app.
    private func handleNativeAppTermination(_ app: NSRunningApplication) {
        // Find the game ID associated with this running app.
        guard let (gameID, _) = runningApps.first(where: { $0.value.processIdentifier == app.processIdentifier }) else {
            return
        }

        let elapsed = calculateElapsedTime(for: gameID)
        runningApps.removeValue(forKey: gameID)
        launchTimestamps.removeValue(forKey: gameID)
        
        if let handler = exitHandlers.removeValue(forKey: gameID) {
            handler(elapsed)
        }
    }

    // MARK: - Native App Monitoring

    /// Launches and monitors a native macOS `.app` bundle.
    ///
    /// Uses `NSWorkspace.openApplication(at:configuration:)` to launch the app,
    /// then tracks it via workspace termination notifications.
    ///
    /// - Parameters:
    ///   - gameID: The UUID of the game being launched.
    ///   - appURL: The file URL of the `.app` bundle.
    ///   - onExit: Closure called when the app quits, with the elapsed play time.
    /// - Throws: An error if the app fails to launch.
    func launchAndMonitorNativeApp(gameID: UUID, appURL: URL, onExit: @escaping @MainActor (TimeInterval) -> Void) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        let app = try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        runningApps[gameID] = app
        launchTimestamps[gameID] = Date()
        exitHandlers[gameID] = onExit
    }

    // MARK: - Child Process Monitoring

    /// Registers a child `Process` for monitoring.
    ///
    /// When the process terminates, the game's status will be updated
    /// and play time calculated.
    ///
    /// - Parameters:
    ///   - gameID: The UUID of the game.
    ///   - process: The running `Foundation.Process` instance.
    ///   - onExit: Closure called when the process quits, with the elapsed play time.
    func monitorProcess(gameID: UUID, process: Process, onExit: @escaping @MainActor (TimeInterval) -> Void) {
        runningProcesses[gameID] = process
        launchTimestamps[gameID] = Date()
        exitHandlers[gameID] = onExit

        // Capture gameID for the termination handler closure.
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let elapsed = self.calculateElapsedTime(for: gameID)
                self.runningProcesses.removeValue(forKey: gameID)
                self.launchTimestamps.removeValue(forKey: gameID)
                
                if let handler = self.exitHandlers.removeValue(forKey: gameID) {
                    handler(elapsed)
                }
            }
        }
    }

    // MARK: - Stop

    /// Stops a running game process.
    ///
    /// For native apps, sends a terminate request. For child processes,
    /// sends SIGTERM and falls back to SIGKILL after 5 seconds.
    ///
    /// - Parameter gameID: The UUID of the game to stop.
    func stopGame(gameID: UUID) {
        if let app = runningApps[gameID] {
            // Try graceful termination first.
            app.terminate()

            // Force-kill after 5 seconds if still running.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(5))
                if !app.isTerminated {
                    app.forceTerminate()
                }
            }
        }

        if let process = runningProcesses[gameID], process.isRunning {
            // Send SIGTERM for graceful shutdown.
            process.terminate()

            // Force-kill after 5 seconds if still running.
            Task {
                try? await Task.sleep(for: .seconds(5))
                if process.isRunning {
                    process.interrupt() // Sends SIGINT
                    try? await Task.sleep(for: .seconds(1))
                    if process.isRunning {
                        kill(process.processIdentifier, SIGKILL)
                    }
                }
            }
        }
    }

    // MARK: - Query

    /// Whether a game is currently being monitored (i.e., running).
    func isGameRunning(gameID: UUID) -> Bool {
        runningApps[gameID] != nil || runningProcesses[gameID] != nil
    }

    // MARK: - Private

    /// Calculates the elapsed time since a game was launched.
    private func calculateElapsedTime(for gameID: UUID) -> TimeInterval {
        guard let launchTime = launchTimestamps[gameID] else { return 0 }
        return Date().timeIntervalSince(launchTime)
    }
}
