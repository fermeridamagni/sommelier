import SwiftData
import SwiftUI

/// Dashboard view showing a welcome greeting, the last played game,
/// recent activity, and aggregate library statistics.
///
/// Adapts to empty states — when no games exist, displays a welcoming
/// `ContentUnavailableView` with instructions to scan a library.
struct HomeView: View {

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = HomeViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                // Greeting header
                greetingHeader
                    .padding(.top, 8)

                if viewModel.totalGamesCount == 0 {
                    emptyState
                } else {
                    // Continue Playing — hero card for last played game
                    if let lastGame = viewModel.lastPlayedGame {
                        continuePlayingCard(game: lastGame)
                    }

                    // Recent Activity — horizontal scroll of recent games
                    if !viewModel.recentGames.isEmpty {
                        recentActivitySection
                    }

                    // At a Glance — stats row
                    statsRow
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
        .navigationTitle("Home")
        .onAppear {
            viewModel.loadDashboardData(context: modelContext)
        }
    }

    // MARK: - Greeting

    /// Time-of-day greeting with a subtle welcome message.
    private var greetingHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(viewModel.greeting)
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Here's what's happening in your library.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Empty State

    /// Shown when the library has no games.
    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Games Yet", systemImage: "gamecontroller")
        } description: {
            Text("Head to the Library tab and scan your platforms to import your games.")
        } actions: {
            // No direct action — guide to Library tab
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    // MARK: - Continue Playing

    /// Large hero card featuring the most recently played game.
    private func continuePlayingCard(game: Game) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Continue Playing")
                .font(.headline)
                .foregroundStyle(.secondary)

            ZStack(alignment: .bottomLeading) {
                // Hero image or gradient placeholder
                heroImage(for: game)
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                // Gradient scrim + game info
                VStack(alignment: .leading, spacing: 6) {
                    Text(game.name)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)

                    HStack(spacing: 12) {
                        PlatformIcon(platform: game.platformType, size: 14)
                        Text(game.platformType.displayName)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))

                        if let lastPlayed = game.lastPlayed {
                            Text("•")
                                .foregroundStyle(.white.opacity(0.5))
                            Text(lastPlayed, style: .relative)
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(
                        colors: [.black.opacity(0.8), .clear],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                )
            }
            .overlay(alignment: .center) {
                // Play button overlay
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(radius: 8)
            }
        }
    }

    /// Loads a hero image from the game's file path, or shows a gradient placeholder.
    @ViewBuilder
    private func heroImage(for game: Game) -> some View {
        if let heroPath = game.heroImagePath,
           let nsImage = NSImage(contentsOfFile: heroPath) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.4),
                    Color.accentColor.opacity(0.15),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay {
                Image(systemName: "gamecontroller")
                    .font(.system(size: 40))
                    .foregroundStyle(.white.opacity(0.2))
            }
        }
    }

    // MARK: - Recent Activity

    /// Horizontal scroll of recent game cover thumbnails.
    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Activity")
                .font(.headline)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(viewModel.recentGames) { game in
                        recentGameThumbnail(game: game)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    /// Small cover thumbnail for a recent game.
    private func recentGameThumbnail(game: Game) -> some View {
        VStack(spacing: 8) {
            // Cover image
            Group {
                if let coverPath = game.coverImagePath,
                   let nsImage = NSImage(contentsOfFile: coverPath) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(3 / 4, contentMode: .fill)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.accentColor.opacity(0.3),
                                    Color.accentColor.opacity(0.1),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay {
                            Image(systemName: "gamecontroller")
                                .foregroundStyle(.white.opacity(0.3))
                        }
                }
            }
            .frame(width: 100, height: 133)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(game.name)
                .font(.caption)
                .lineLimit(1)
                .frame(width: 100)
        }
    }

    // MARK: - Stats Row

    /// "At a Glance" stats in rounded rectangle cards.
    private var statsRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("At a Glance")
                .font(.headline)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                statCard(
                    icon: "gamecontroller",
                    value: "\(viewModel.totalGamesCount)",
                    label: "Total Games"
                )

                statCard(
                    icon: "square.stack.3d.up",
                    value: "\(viewModel.connectedPlatformsCount)",
                    label: "Platforms"
                )

                statCard(
                    icon: "clock",
                    value: formattedWeeklyPlayTime,
                    label: "This Week"
                )
            }
        }
    }

    /// Individual stat card with icon, value, and label.
    private func statCard(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.accentColor)

            Text(value)
                .font(.title3)
                .fontWeight(.semibold)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    /// Formats the weekly play time into a human-readable string.
    private var formattedWeeklyPlayTime: String {
        let hours = Int(viewModel.weeklyPlayTime) / 3600
        let minutes = (Int(viewModel.weeklyPlayTime) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

#Preview {
    HomeView()
}
