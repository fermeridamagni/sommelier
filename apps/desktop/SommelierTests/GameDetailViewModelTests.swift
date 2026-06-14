import Testing
import Foundation
@testable import Sommelier

/// Tests for `GameDetailViewModel` computed properties and state transitions.
@Suite("GameDetailViewModel Tests")
struct GameDetailViewModelTests {

    private func makeGame(
        name: String = "Test Game",
        platform: Platform = .steam,
        isInstalled: Bool = true,
        status: GameStatus = .idle,
        totalPlayTime: TimeInterval = 0,
        lastPlayed: Date? = nil
    ) -> Game {
        Game(
            name: name,
            platform: platform,
            executablePath: "/fake/path",
            isNative: platform == .macNative,
            lastPlayed: lastPlayed,
            totalPlayTime: totalPlayTime,
            status: status,
            isInstalled: isInstalled
        )
    }

    // MARK: - Primary Action Label

    @Test("Play label for installed idle game")
    @MainActor
    func playLabelInstalled() {
        let game = makeGame(isInstalled: true, status: .idle)
        let vm = GameDetailViewModel(game: game)
        #expect(vm.primaryActionLabel == "Play")
    }

    @Test("Install label for non-installed idle game")
    @MainActor
    func installLabelNotInstalled() {
        let game = makeGame(isInstalled: false, status: .idle)
        let vm = GameDetailViewModel(game: game)
        #expect(vm.primaryActionLabel == "Install")
    }

    @Test("Stop label when game is running")
    @MainActor
    func stopLabelRunning() {
        let game = makeGame(status: .running)
        let vm = GameDetailViewModel(game: game)
        #expect(vm.primaryActionLabel == "Stop")
    }

    @Test("Downloading label")
    @MainActor
    func downloadingLabel() {
        let game = makeGame(status: .downloading)
        let vm = GameDetailViewModel(game: game)
        #expect(vm.primaryActionLabel == "Downloading…")
    }

    // MARK: - Can Perform Primary Action

    @Test("Can perform action when idle")
    @MainActor
    func canPerformIdle() {
        let game = makeGame(status: .idle)
        let vm = GameDetailViewModel(game: game)
        #expect(vm.canPerformPrimaryAction == true)
    }

    @Test("Can perform action when running (stop)")
    @MainActor
    func canPerformRunning() {
        let game = makeGame(status: .running)
        let vm = GameDetailViewModel(game: game)
        #expect(vm.canPerformPrimaryAction == true)
    }

    @Test("Cannot perform action when downloading")
    @MainActor
    func cannotPerformDownloading() {
        let game = makeGame(status: .downloading)
        let vm = GameDetailViewModel(game: game)
        #expect(vm.canPerformPrimaryAction == false)
    }

    // MARK: - Formatted Play Time

    @Test("Not played shows correct text")
    @MainActor
    func notPlayed() {
        let game = makeGame(totalPlayTime: 0)
        let vm = GameDetailViewModel(game: game)
        #expect(vm.formattedPlayTime == "Not played")
    }

    @Test("Minutes only")
    @MainActor
    func minutesOnly() {
        let game = makeGame(totalPlayTime: 1800) // 30 minutes
        let vm = GameDetailViewModel(game: game)
        #expect(vm.formattedPlayTime == "30m")
    }

    @Test("Hours and minutes")
    @MainActor
    func hoursAndMinutes() {
        let game = makeGame(totalPlayTime: 5400) // 1h 30m
        let vm = GameDetailViewModel(game: game)
        #expect(vm.formattedPlayTime == "1h 30m")
    }

    // MARK: - Formatted Last Played

    @Test("Never played")
    @MainActor
    func neverPlayed() {
        let game = makeGame(lastPlayed: nil)
        let vm = GameDetailViewModel(game: game)
        #expect(vm.formattedLastPlayed == "Never")
    }
}
