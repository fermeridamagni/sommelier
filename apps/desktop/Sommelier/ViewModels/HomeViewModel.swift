import Foundation
import SwiftData
import SwiftUI

/// Drives the Home dashboard, surfacing recently played games and
/// aggregate statistics from the user's SwiftData library.
///
/// All data is fetched on-demand via `loadDashboardData(context:)` so
/// the view can refresh when appearing or when the library changes.
@Observable
final class HomeViewModel {

    /// The 10 most recently played games, sorted by `lastPlayed` descending.
    var recentGames: [Game] = []

    /// Total number of games in the library.
    var totalGamesCount: Int = 0

    /// Number of distinct platforms that have at least one game.
    var connectedPlatformsCount: Int = 0

    /// Total play time across all games during the current week (Mon–Sun).
    var weeklyPlayTime: TimeInterval = 0

    /// Time-of-day greeting computed from the current hour.
    var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Good night"
        }
    }

    /// The single most recently played game, used for the hero "Continue Playing" card.
    var lastPlayedGame: Game? {
        recentGames.first
    }

    // MARK: - Data Loading

    /// Fetches dashboard data from SwiftData.
    ///
    /// - Parameter context: The `ModelContext` provided by the SwiftUI environment.
    func loadDashboardData(context: ModelContext) {
        // Fetch all games
        let descriptor = FetchDescriptor<Game>(
            sortBy: [SortDescriptor(\.lastPlayed, order: .reverse)]
        )

        do {
            let allGames = try context.fetch(descriptor)
            totalGamesCount = allGames.count

            // Recent games: top 10 that have been played
            recentGames = Array(
                allGames
                    .filter { $0.lastPlayed != nil }
                    .prefix(10)
            )

            // Count distinct platforms
            let platforms = Set(allGames.map(\.platformRawValue))
            connectedPlatformsCount = platforms.count

            // Calculate weekly play time
            // Sum totalPlayTime for games played this week
            let calendar = Calendar.current
            let now = Date()
            guard let weekStart = calendar.date(
                from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
            ) else {
                weeklyPlayTime = 0
                return
            }

            weeklyPlayTime = allGames
                .filter { game in
                    guard let lastPlayed = game.lastPlayed else { return false }
                    return lastPlayed >= weekStart
                }
                .reduce(0) { $0 + $1.totalPlayTime }
        } catch {
            // Silently handle fetch errors — dashboard shows empty state
            recentGames = []
            totalGamesCount = 0
            connectedPlatformsCount = 0
            weeklyPlayTime = 0
        }
    }
}
