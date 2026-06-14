import Testing
import Foundation
@testable import Sommelier

/// Tests for `LibraryViewModel` filtering, sorting, and search logic.
@Suite("LibraryViewModel Tests")
struct LibraryViewModelTests {

    /// Helper to create a Game for testing.
    private func makeGame(
        name: String,
        platform: Platform = .steam,
        isInstalled: Bool = true,
        lastPlayed: Date? = nil,
        dateAdded: Date = Date()
    ) -> Game {
        Game(
            name: name,
            platform: platform,
            executablePath: "/fake/path",
            isNative: platform == .macNative,
            lastPlayed: lastPlayed,
            isInstalled: isInstalled,
            dateAdded: dateAdded
        )
    }

    @Test("Search filter is case-insensitive")
    @MainActor
    func searchFilterCaseInsensitive() {
        let vm = LibraryViewModel()
        vm.games = [
            makeGame(name: "Cyberpunk 2077"),
            makeGame(name: "The Witcher 3"),
            makeGame(name: "Elden Ring"),
        ]

        vm.searchText = "cyber"
        #expect(vm.filteredGames.count == 1)
        #expect(vm.filteredGames.first?.name == "Cyberpunk 2077")
    }

    @Test("Platform filter shows only matching games")
    @MainActor
    func platformFilter() {
        let vm = LibraryViewModel()
        vm.games = [
            makeGame(name: "Steam Game", platform: .steam),
            makeGame(name: "Epic Game", platform: .epic),
            makeGame(name: "Mac Game", platform: .macNative),
        ]

        vm.selectedPlatform = .epic
        #expect(vm.filteredGames.count == 1)
        #expect(vm.filteredGames.first?.name == "Epic Game")
    }

    @Test("Install filter shows installed games")
    @MainActor
    func installFilterInstalled() {
        let vm = LibraryViewModel()
        vm.games = [
            makeGame(name: "Installed Game", isInstalled: true),
            makeGame(name: "Uninstalled Game", isInstalled: false),
        ]

        vm.selectedInstallFilter = .installed
        #expect(vm.filteredGames.count == 1)
        #expect(vm.filteredGames.first?.name == "Installed Game")
    }

    @Test("Install filter shows not-installed games")
    @MainActor
    func installFilterNotInstalled() {
        let vm = LibraryViewModel()
        vm.games = [
            makeGame(name: "Installed Game", isInstalled: true),
            makeGame(name: "Uninstalled Game", isInstalled: false),
        ]

        vm.selectedInstallFilter = .notInstalled
        #expect(vm.filteredGames.count == 1)
        #expect(vm.filteredGames.first?.name == "Uninstalled Game")
    }

    @Test("Sort by name orders alphabetically")
    @MainActor
    func sortByName() {
        let vm = LibraryViewModel()
        vm.games = [
            makeGame(name: "Zelda"),
            makeGame(name: "Apex"),
            makeGame(name: "Mario"),
        ]
        vm.sortOrder = .name
        let names = vm.filteredGames.map(\.name)
        #expect(names == ["Apex", "Mario", "Zelda"])
    }

    @Test("Sort by last played orders recent first")
    @MainActor
    func sortByLastPlayed() {
        let now = Date()
        let vm = LibraryViewModel()
        vm.games = [
            makeGame(name: "Old", lastPlayed: now.addingTimeInterval(-3600)),
            makeGame(name: "Recent", lastPlayed: now),
            makeGame(name: "Never"),
        ]
        vm.sortOrder = .lastPlayed
        let names = vm.filteredGames.map(\.name)
        #expect(names == ["Recent", "Old", "Never"])
    }

    @Test("Sort by date added orders newest first")
    @MainActor
    func sortByDateAdded() {
        let now = Date()
        let vm = LibraryViewModel()
        vm.games = [
            makeGame(name: "Oldest", dateAdded: now.addingTimeInterval(-7200)),
            makeGame(name: "Newest", dateAdded: now),
            makeGame(name: "Middle", dateAdded: now.addingTimeInterval(-3600)),
        ]
        vm.sortOrder = .dateAdded
        let names = vm.filteredGames.map(\.name)
        #expect(names == ["Newest", "Middle", "Oldest"])
    }

    @Test("Empty state detection")
    @MainActor
    func emptyState() {
        let vm = LibraryViewModel()
        vm.games = []
        #expect(vm.isEmpty == true)
        vm.games = [makeGame(name: "Test")]
        #expect(vm.isEmpty == false)
    }

    @Test("Filters can be combined")
    @MainActor
    func combinedFilters() {
        let vm = LibraryViewModel()
        vm.games = [
            makeGame(name: "Steam Installed", platform: .steam, isInstalled: true),
            makeGame(name: "Steam Not Installed", platform: .steam, isInstalled: false),
            makeGame(name: "Epic Installed", platform: .epic, isInstalled: true),
        ]

        vm.selectedPlatform = .steam
        vm.selectedInstallFilter = .installed
        vm.searchText = "steam"
        #expect(vm.filteredGames.count == 1)
        #expect(vm.filteredGames.first?.name == "Steam Installed")
    }
}
