import Foundation
import SwiftData
import SwiftUI

/// Drives the game detail sheet — launching games, managing Wine bottles,
/// and fetching artwork from external APIs.
///
/// For native macOS games, `primaryAction()` launches the executable directly.
/// For Windows games, it creates or reuses a GPTK/Wine bottle before launching.
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

    // MARK: - Init

    init(game: Game) {
        self.game = game
    }

    // MARK: - Computed Properties

    /// Label for the primary action button based on current game state.
    var primaryActionLabel: String {
        switch game.status {
        case .idle:
            return game.isInstalled ? "Play" : "Install"
        case .downloading:
            return "Downloading…"
        case .installing:
            return "Installing…"
        case .running:
            return "Running…"
        case .updating:
            return "Updating…"
        case .error:
            return "Retry"
        }
    }

    /// Color for the primary action button.
    var primaryActionColor: Color {
        switch game.status {
        case .idle:
            return game.isInstalled ? .green : Color.accentColor
        case .downloading, .installing, .updating:
            return .blue
        case .running:
            return .secondary
        case .error:
            return .red
        }
    }

    /// Whether the primary action button is interactive.
    var canPerformPrimaryAction: Bool {
        switch game.status {
        case .idle, .error: true
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

    /// Executes the primary action: launch for installed games, install otherwise.
    ///
    /// Native macOS games are launched directly. Windows games go through
    /// bottle creation/verification before launching via GPTK/Wine.
    func primaryAction() {
        guard canPerformPrimaryAction else { return }

        if game.isInstalled {
            launchGame()
        } else {
            installGame()
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

    /// Launches the game executable.
    private func launchGame() {
        isLaunching = true
        launchProgress = "Starting \(game.name)…"
        game.statusRawValue = GameStatus.running.rawValue

        Task { @MainActor in
            if game.isNative {
                launchProgress = "Launching native app…"
            } else {
                launchProgress = "Preparing Wine bottle…"
                try? await Task.sleep(for: .seconds(1))
                launchProgress = "Starting via GPTK…"
            }

            // In production: actually launch the process
            try? await Task.sleep(for: .seconds(1))
            launchProgress = ""
            isLaunching = false
            // Note: status would be set back to .idle when the process exits
        }
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
