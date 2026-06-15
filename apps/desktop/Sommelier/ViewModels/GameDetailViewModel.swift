import Foundation
import SwiftData
import SwiftUI

/// Drives the game detail sheet — launching games, managing Wine bottles,
/// and fetching artwork from external APIs.
///
/// For native macOS games, `primaryAction()` launches the executable directly
/// via `ProcessMonitor`, which tracks the running app and reports when it exits.
/// For Windows games, it creates or reuses a GPTK/Wine bottle before launching.
///
/// The stop button is enabled while a game is running, allowing the user to
/// terminate the process gracefully (SIGTERM → 5s → SIGKILL fallback).
@MainActor
@Observable
final class GameDetailViewModel {

    /// The game being viewed.
    var game: Game

    /// Whether a launch operation is in progress.
    var isLaunching: Bool = false

    /// Progress description during launch (e.g. "Creating bottle…", "Starting…").
    var launchProgress: String = ""

    /// The Wine/GPTK bottle associated with this game, if any.
    var bottle: Bottle?

    /// Whether the confirm-delete dialog is showing.
    var showingDeleteConfirmation: Bool = false

    /// The process monitor used to track game lifecycle.
    private let processMonitor: ProcessMonitor

    // MARK: - Init

    init(game: Game, processMonitor: ProcessMonitor = .shared) {
        self.game = game
        self.processMonitor = processMonitor
    }

    // MARK: - Computed Properties

    /// Label for the primary action button based on current game state.
    ///
    /// Shows "Stop" when running so the user can terminate the process.
    var primaryActionLabel: String {
        switch game.status {
        case .idle:
            return game.isInstalled ? "Play" : "Install"
        case .downloading:
            return "Downloading…"
        case .installing:
            return "Installing…"
        case .running:
            return "Stop"
        case .updating:
            return "Updating…"
        case .error:
            return "Retry"
        }
    }

    /// Color for the primary action button.
    ///
    /// Red when running (stop action), green for play, accent for install.
    var primaryActionColor: Color {
        switch game.status {
        case .idle:
            return game.isInstalled ? .green : Color.accentColor
        case .downloading, .installing, .updating:
            return .blue
        case .running:
            return .red
        case .error:
            return .red
        }
    }

    /// Whether the primary action button is interactive.
    ///
    /// Now also returns `true` when `.running` so the stop button is clickable.
    var canPerformPrimaryAction: Bool {
        switch game.status {
        case .idle, .error, .running: true
        default: false
        }
    }

    /// Formatted total play time string.
    var formattedPlayTime: String {
        let hours = Int(game.totalPlayTime) / 3600
        let minutes = (Int(game.totalPlayTime) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "Not played"
        }
    }

    /// Formatted last played date string.
    var formattedLastPlayed: String {
        guard let date = game.lastPlayed else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Methods

    /// Executes the primary action based on game state.
    ///
    /// - **Idle + Installed** → Launch the game
    /// - **Idle + Not Installed** → Install the game
    /// - **Running** → Stop the game
    /// - **Error** → Retry launch
    func primaryAction() {
        guard canPerformPrimaryAction else { return }

        switch game.status {
        case .running:
            stopGame()
        case .idle, .error:
            if game.isInstalled {
                launchGame()
            } else {
                installGame()
            }
        default:
            break
        }
    }

    /// Stops the currently running game process.
    ///
    /// Delegates to `ProcessMonitor.stopGame(gameID:)` which sends SIGTERM
    /// with a 5-second SIGKILL fallback. The `onGameExited` callback will
    /// reset the game status to idle.
    func stopGame() {
        launchProgress = "Stopping \(game.name)…"
        if game.isNative {
            processMonitor.stopGame(gameID: game.id)
        } else {
            Task {
                try? await WineManager.shared.terminate(gameID: game.id)
            }
        }
    }

    /// Fetches high-quality artwork from SteamGridDB or platform APIs.
    func fetchArtwork() {
        // In production: call SteamGridDB API with the stored API key
        // Update game.coverImagePath and game.heroImagePath
    }

    /// Deletes the Wine bottle associated with this game.
    func deleteBottle() {
        guard let bottle = bottle else { return }

        // In production: remove the bottle directory from disk
        let bottlePath = bottle.path
        try? FileManager.default.removeItem(atPath: bottlePath)
        self.bottle = nil
    }

    // MARK: - Private

    /// Launches the game executable using ProcessMonitor for lifecycle tracking.
    ///
    /// For native macOS apps, uses `NSWorkspace.openApplication` via ProcessMonitor.
    /// For Windows games, prepares a Wine bottle then launches via GPTK.
    /// Sets `lastPlayed` to now and status to `.running`.
    private func launchGame() {
        isLaunching = true
        launchProgress = "Starting \(game.name)…"
        game.statusRawValue = GameStatus.running.rawValue
        game.lastPlayed = Date()

        Task { @MainActor in
            do {
                if game.isNative {
                    launchProgress = "Launching native app…"
                    let appURL = URL(fileURLWithPath: game.executablePath)
                    
                    // Strongly capture the Game model so it can be updated even if this ViewModel dies
                    let gameModel = self.game
                    let onExit: @MainActor (TimeInterval) -> Void = { elapsed in
                        gameModel.statusRawValue = GameStatus.idle.rawValue
                        gameModel.totalPlayTime += elapsed
                    }
                    
                    try await processMonitor.launchAndMonitorNativeApp(
                        gameID: game.id,
                        appURL: appURL,
                        onExit: onExit
                    )
                    launchProgress = ""
                    isLaunching = false
                } else {
                    launchProgress = "Preparing Wine bottle…"
                    let wineManager = WineManager.shared
                    let currentBottle: Bottle
                    
                    if let existingBottleID = game.bottleID {
                        let descriptor = FetchDescriptor<Bottle>(predicate: #Predicate { $0.id == existingBottleID })
                        if let existingBottle = try? game.modelContext?.fetch(descriptor).first {
                            currentBottle = existingBottle
                        } else {
                            let bottleData = try await wineManager.createBottle(name: game.name, gameID: game.id)
                            currentBottle = Bottle(id: bottleData.id, name: game.name, path: bottleData.path, wineBinaryPath: bottleData.wineBinaryPath, gameID: game.id)
                            game.modelContext?.insert(currentBottle)
                            game.bottleID = currentBottle.id
                        }
                    } else {
                        let bottleData = try await wineManager.createBottle(name: game.name, gameID: game.id)
                        currentBottle = Bottle(id: bottleData.id, name: game.name, path: bottleData.path, wineBinaryPath: bottleData.wineBinaryPath, gameID: game.id)
                        game.modelContext?.insert(currentBottle)
                        game.bottleID = currentBottle.id
                    }
                    
                    self.bottle = currentBottle
                    
                    launchProgress = "Starting via GPTK…"
                    
                    let onExit: @Sendable (TimeInterval) -> Void = { [weak self] elapsed in
                        Task { @MainActor in
                            self?.handleGameExited(elapsedTime: elapsed)
                        }
                    }
                    
                    try await wineManager.launch(
                        gameID: game.id,
                        executablePath: game.executablePath,
                        installPath: game.installPath,
                        bottlePath: currentBottle.path,
                        wineBinaryPath: currentBottle.wineBinaryPath,
                        environmentVariables: currentBottle.environmentVariables,
                        onExit: onExit
                    )
                    
                    launchProgress = ""
                    isLaunching = false
                }
            } catch {
                launchProgress = "Failed: \(error.localizedDescription)"
                game.statusRawValue = GameStatus.error.rawValue
                isLaunching = false
            }
        }
    }

    /// Called by `ProcessMonitor` when the game process exits.
    ///
    /// Resets game status to idle and accumulates the elapsed play time
    /// into the game's total play time for statistics.
    private func handleGameExited(elapsedTime: TimeInterval) {
        game.statusRawValue = GameStatus.idle.rawValue
        game.totalPlayTime += elapsedTime
        launchProgress = ""
        isLaunching = false
    }

    /// Initiates game installation via the platform's CLI tool.
    private func installGame() {
        isLaunching = true
        game.statusRawValue = GameStatus.downloading.rawValue
        launchProgress = "Starting download…"

        Task { @MainActor in
            // In production: run the appropriate CLI install command
            try? await Task.sleep(for: .seconds(2))
            game.statusRawValue = GameStatus.installing.rawValue
            launchProgress = "Installing…"
            try? await Task.sleep(for: .seconds(1))
            game.isInstalled = true
            game.statusRawValue = GameStatus.idle.rawValue
            launchProgress = ""
            isLaunching = false
        }
    }
}
