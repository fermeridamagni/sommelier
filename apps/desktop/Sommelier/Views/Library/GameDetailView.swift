import SwiftData
import SwiftUI

/// Detail sheet for a game, shown as a modal from the library.
///
/// Features a hero banner with gradient scrim, game metadata,
/// primary action button (Play/Install/Running), and secondary
/// management actions in a disclosure group.
struct GameDetailView: View {

    /// The game to display details for.
    let game: Game

    @State private var viewModel: GameDetailViewModel
    @Environment(\.dismiss) private var dismiss

    init(game: Game) {
        self.game = game
        self._viewModel = State(initialValue: GameDetailViewModel(game: game))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Hero banner
                heroBanner

                // Content
                VStack(alignment: .leading, spacing: 24) {
                    // Game info section
                    infoSection

                    Divider()

                    // Primary action button
                    primaryActionButton

                    // Launch progress
                    if !viewModel.launchProgress.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(viewModel.launchProgress)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    // Secondary actions
                    secondaryActions
                }
                .padding(24)
            }
        }
        .frame(minWidth: 480)
    }

    // MARK: - Hero Banner

    /// Full-width hero image with gradient scrim and title overlay.
    private var heroBanner: some View {
        ZStack(alignment: .bottomLeading) {
            // Hero image or placeholder
            Group {
                if let heroPath = game.heroImagePath,
                   let nsImage = NSImage(contentsOfFile: heroPath) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.4),
                            Color.accentColor.opacity(0.1),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .overlay {
                        Image(systemName: "gamecontroller")
                            .font(.system(size: 48))
                            .foregroundStyle(.white.opacity(0.15))
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 250)
            .clipped()

            // Gradient scrim
            LinearGradient(
                colors: [.black.opacity(0.7), .clear],
                startPoint: .bottom,
                endPoint: .center
            )

            // Title overlay
            VStack(alignment: .leading, spacing: 6) {
                Text(game.name)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)

                HStack(spacing: 8) {
                    PlatformIcon(platform: game.platformType, size: 14)
                    Text(game.platformType.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))

                    if game.isNative {
                        Text("• Native")
                            .font(.subheadline)
                            .foregroundStyle(.green.opacity(0.8))
                    }
                }
            }
            .padding(24)
        }
    }

    // MARK: - Info Section

    /// Grid showing game metadata: platform, status, play time, last played.
    private var infoSection: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
            ],
            spacing: 16
        ) {
            infoItem(label: "Platform", value: game.platformType.displayName, icon: "square.stack.3d.up")
            infoItem(label: "Status", value: game.status.rawValue.capitalized, icon: "circle.fill")
            infoItem(label: "Play Time", value: viewModel.formattedPlayTime, icon: "clock")
            infoItem(label: "Last Played", value: viewModel.formattedLastPlayed, icon: "calendar")
        }
    }

    /// Individual metadata item with icon, label, and value.
    private func infoItem(label: String, value: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            Spacer()
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Primary Action

    /// Full-width action button colored by game state.
    private var primaryActionButton: some View {
        Button {
            viewModel.primaryAction()
        } label: {
            HStack {
                if !viewModel.canPerformPrimaryAction {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }

                Text(viewModel.primaryActionLabel)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .tint(viewModel.primaryActionColor)
        .controlSize(.large)
        .disabled(!viewModel.canPerformPrimaryAction)
    }

    // MARK: - Secondary Actions

    /// Disclosure group with management actions.
    private var secondaryActions: some View {
        DisclosureGroup("Advanced") {
            VStack(alignment: .leading, spacing: 12) {
                if let installPath = game.installPath {
                    Button {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: installPath)
                    } label: {
                        Label("Open Install Location", systemImage: "folder")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                }

                if game.bottleID != nil {
                    Button {
                        viewModel.deleteBottle()
                    } label: {
                        Label("Delete Wine Bottle", systemImage: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                }

                Button(role: .destructive) {
                    viewModel.showingDeleteConfirmation = true
                } label: {
                    Label("Remove from Library", systemImage: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }
            .padding(.top, 8)
        }
        .alert("Delete Game?", isPresented: $viewModel.showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                dismiss()
            }
        } message: {
            Text("This will remove \"\(game.name)\" from your library. Game files won't be deleted.")
        }
    }
}

#Preview {
    Text("GameDetailView requires a Game @Model instance")
        .foregroundStyle(.secondary)
}
