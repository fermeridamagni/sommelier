import Foundation
import SwiftData
import SwiftUI

// MARK: - SortOrder

/// Sorting options for the game library grid.
enum SortOrder: String, CaseIterable, Identifiable {
    case name
    case lastPlayed
    case platform
    case dateAdded

    var id: String { rawValue }

    /// Human-readable label for picker display.
    var label: String {
        switch self {
        case .name: "Name"
        case .lastPlayed: "Last Played"
        case .platform: "Platform"
        case .dateAdded: "Date Added"
        }
    }

    /// SF Symbol for the sort option.
    var systemImage: String {
        switch self {
        case .name: "textformat.abc"
        case .lastPlayed: "clock"
        case .platform: "square.stack.3d.up"
        case .dateAdded: "calendar"
        }
    }
}

// MARK: - InstallFilter

/// Filters games by installation status in the library grid.
enum InstallFilter: String, CaseIterable, Identifiable {
    /// Show all games regardless of installation status.
    case all

    /// Show only games that are currently installed on disk.
    case installed

    /// Show only games that are not installed (available for download).
    case notInstalled

    var id: String { rawValue }

    /// Human-readable label for the filter pill.
    var label: String {
        switch self {
        case .all: "All"
        case .installed: "Installed"
        case .notInstalled: "Not Installed"
        }
    }

    /// SF Symbol for the filter pill.
    var systemImage: String {
        switch self {
        case .all: "square.grid.2x2"
        case .installed: "checkmark.circle"
        case .notInstalled: "arrow.down.circle"
        }
    }
}

// MARK: - LibraryViewModel

/// Manages the game library grid view — loading, filtering, sorting,
/// scanning for new games, and deleting existing entries.
///
/// Uses SwiftData `ModelContext` for persistence. The `filteredGames`
/// computed property chains search text, platform filter, and sort order.
@MainActor
@Observable
final class LibraryViewModel {

    /// All games loaded from SwiftData.
    var games: [Game] = []

    /// Current search query from the `.searchable` modifier.
    var searchText: String = ""

    /// Platform filter — `nil` means show all platforms.
    var selectedPlatform: Platform?

    /// How games are sorted in the grid.
    var sortOrder: SortOrder = .name

    /// Installation status filter — `.all` by default.
    var selectedInstallFilter: InstallFilter = .all

    /// Whether a library scan is currently in progress.
    var isScanning: Bool = false

    // MARK: - Computed Properties

    /// Games filtered by search text, platform, and install status, then sorted.
    var filteredGames: [Game] {
        var result = games

        // Platform filter
        if let platform = selectedPlatform {
            result = result.filter { $0.platformRawValue == platform.rawValue }
        }

        // Install status filter
        switch selectedInstallFilter {
        case .all:
            break
        case .installed:
            result = result.filter { $0.isInstalled }
        case .notInstalled:
            result = result.filter { !$0.isInstalled }
        }

        // Search filter (case-insensitive)
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { $0.name.lowercased().contains(query) }
        }

        // Sort
        switch sortOrder {
        case .name:
            result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .lastPlayed:
            result.sort { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
        case .platform:
            result.sort { $0.platformRawValue < $1.platformRawValue }
        case .dateAdded:
            result.sort { $0.dateAdded > $1.dateAdded }
        }

        return result
    }

    /// Number of installed games (for badge display).
    var installedCount: Int {
        games.filter { $0.isInstalled }.count
    }

    /// Number of not-installed games (for badge display).
    var notInstalledCount: Int {
        games.filter { !$0.isInstalled }.count
    }

    /// Whether the library is empty (no games at all, not just filtered).
    var isEmpty: Bool {
        games.isEmpty
    }

    // MARK: - Methods

    /// Fetches all games from SwiftData.
    ///
    /// - Parameter context: The SwiftUI environment's `ModelContext`.
    func loadGames(context: ModelContext) {
        let descriptor = FetchDescriptor<Game>(
            sortBy: [SortDescriptor(\.name)]
        )
        do {
            games = try context.fetch(descriptor)
        } catch {
            games = []
        }
    }

    /// Scans all platform CLI tools for newly installed games and imports them.
    func scanLibrary(context: ModelContext) {
        if isScanning { return }
        isScanning = true

        Task { @MainActor in
            let libraryManager = LibraryManager()
            await libraryManager.scanAllPlatforms(context: context)
            
            // Reload the games after scan completes
            self.loadGames(context: context)
            isScanning = false
        }
    }

    /// Opens a file picker to manually add a macOS app or Windows executable.
    func addGameManually(context: ModelContext) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            .application, // .app
            .init(filenameExtension: "exe")! // .exe
        ]
        panel.message = "Select a macOS App or Windows Executable to add to your library"
        panel.prompt = "Add Game"

        if panel.runModal() == .OK, let url = panel.url {
            let isApp = url.pathExtension == "app"
            let name = isApp ? url.deletingPathExtension().lastPathComponent : url.lastPathComponent
            
            let platform: Platform = isApp ? .macNative : .windowsApp
            
            let newGame = Game(
                name: name,
                platform: platform,
                executablePath: url.path,
                installPath: isApp ? url.path : url.deletingLastPathComponent().path,
                isNative: isApp,
                isInstalled: true
            )
            
            context.insert(newGame)
            do {
                try context.save()
                loadGames(context: context)
            } catch {
                // Handle save error silently for now
            }
        }
    }

    /// Deletes a game from the library.
    ///
    /// - Parameters:
    ///   - game: The game to remove.
    ///   - context: The SwiftUI environment's `ModelContext`.
    func deleteGame(_ game: Game, context: ModelContext) {
        context.delete(game)
        do {
            try context.save()
            games.removeAll { $0.id == game.id }
        } catch {
            // Silently handle — could surface error in future
        }
    }
}
