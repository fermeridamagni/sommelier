import SwiftUI

/// Game tile card for the library grid.
///
/// Displays a cover image with a 3:4 aspect ratio, the game's name,
/// a platform badge, and an optional status overlay. Features a subtle
/// hover scale-up effect with increased shadow for interactivity feedback.
struct GameCardView: View {

    /// The game to display.
    let game: Game

    /// Tracks mouse hover state for the scale animation.
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Cover image with 3:4 aspect ratio
            coverImage
                .aspectRatio(3 / 4, contentMode: .fit)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 12,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 12
                    )
                )
                .overlay(alignment: .topTrailing) {
                    // Platform badge in top-right corner
                    PlatformIcon(platform: game.platformType, size: 12)
                        .padding(6)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                        .padding(8)
                }
                .overlay(alignment: .bottomLeading) {
                    // Status badge overlay (hidden when idle)
                    StatusBadge(status: game.status)
                        .padding(8)
                }

            // Game info bar
            VStack(alignment: .leading, spacing: 4) {
                Text(game.name)
                    .font(.headline)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(height: 40, alignment: .topLeading)

                Text(game.platformType.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 12,
                    bottomTrailingRadius: 12,
                    topTrailingRadius: 0
                )
            )
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .shadow(
                    color: .black.opacity(isHovered ? 0.25 : 0.12),
                    radius: isHovered ? 12 : 6,
                    y: isHovered ? 6 : 3
                )
        )
        .scaleEffect(isHovered ? 1.03 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    // MARK: - Cover Image

    /// Loads the cover image from the game's file path, shows the native app icon
    /// for macOS apps, or falls back to a gradient placeholder.
    @ViewBuilder
    private var coverImage: some View {
        if let coverPath = game.coverImagePath,
           let nsImage = NSImage(contentsOfFile: coverPath) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else if game.isNative, !game.executablePath.isEmpty,
                  FileManager.default.fileExists(atPath: game.executablePath) {
            // Native macOS app — show the actual app icon centered on a gradient.
            // NSWorkspace.icon(forFile:) reads the .app bundle's icon catalog
            // and returns a high-resolution NSImage without manual plist parsing.
            let appIcon = NSWorkspace.shared.icon(forFile: game.executablePath)
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.20),
                    Color.accentColor.opacity(0.05),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay {
                Image(nsImage: appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 64, height: 64)
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            }
        } else {
            // Gradient placeholder with game controller icon
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.35),
                    Color.accentColor.opacity(0.10),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "gamecontroller")
                        .font(.system(size: 28))
                        .foregroundStyle(.white.opacity(0.25))

                    Text(game.name)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.3))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
            }
        }
    }
}

#Preview {
    HStack {
        // Preview requires a Game model instance — shown for layout reference
        Text("GameCardView requires a Game @Model instance")
            .foregroundStyle(.secondary)
    }
    .frame(width: 200, height: 320)
}
