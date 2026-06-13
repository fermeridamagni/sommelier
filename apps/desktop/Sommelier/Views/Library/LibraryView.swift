import SwiftData
import SwiftUI

/// Searchable game library grid with platform filter pills, sorting,
/// and a toolbar scan button.
///
/// Displays games as `GameCardView` tiles in an adaptive grid.
/// Search, platform filtering, and sorting are all driven by `LibraryViewModel`.
struct LibraryView: View {

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = LibraryViewModel()

    /// The game currently shown in the detail sheet.
    @State private var selectedGame: Game?

    var body: some View {
        VStack(spacing: 0) {
            // Platform filter pills
            platformFilterBar
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 8)

            if viewModel.isEmpty {
                emptyLibraryState
            } else if viewModel.filteredGames.isEmpty {
                noResultsState
            } else {
                gameGrid
            }
        }
        .navigationTitle("Library")
        .searchable(text: $viewModel.searchText, prompt: "Search games…")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 12) {
                    // Sort picker
                    Menu {
                        ForEach(SortOrder.allCases) { order in
                            Button {
                                viewModel.sortOrder = order
                            } label: {
                                Label(order.label, systemImage: order.systemImage)
                            }
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }

                    // Add Game button
                    Button {
                        viewModel.addGameManually(context: modelContext)
                    } label: {
                        Label("Add Game", systemImage: "plus")
                    }

                    // Scan button
                    Button {
                        viewModel.scanLibrary(context: modelContext)
                    } label: {
                        if viewModel.isScanning {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Scan Library", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(viewModel.isScanning)
                }
            }
        }
        .sheet(item: $selectedGame) { game in
            GameDetailView(game: game)
                .presentationDetents([.medium, .large])
        }
        .onAppear {
            viewModel.loadGames(context: modelContext)
            viewModel.scanLibrary(context: modelContext)
        }
    }

    // MARK: - Platform Filter Bar

    /// Horizontal row of capsule-shaped platform filter buttons.
    private var platformFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // "All" pill
                filterPill(label: "All", icon: "square.grid.2x2", isSelected: viewModel.selectedPlatform == nil) {
                    viewModel.selectedPlatform = nil
                }

                ForEach(Platform.allCases, id: \.self) { platform in
                    filterPill(
                        label: platform.displayName,
                        icon: platform.systemImage,
                        isSelected: viewModel.selectedPlatform == platform
                    ) {
                        viewModel.selectedPlatform = platform
                    }
                }
            }
        }
    }

    /// Individual filter pill button.
    private func filterPill(label: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .contentShape(Capsule())
                .background(
                    isSelected ? Color.accentColor.opacity(0.2) : Color.clear,
                    in: Capsule()
                )
                .overlay(
                    Capsule()
                        .strokeBorder(
                            isSelected ? Color.accentColor : Color.secondary.opacity(0.3),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3), value: isSelected)
    }

    // MARK: - Game Grid

    /// Adaptive grid of game cards.
    private var gameGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 180))],
                spacing: 20
            ) {
                ForEach(viewModel.filteredGames) { game in
                    GameCardView(game: game)
                        .onTapGesture {
                            selectedGame = game
                        }
                        .contextMenu {
                            Button("View Details") { selectedGame = game }
                            Divider()
                            Button("Delete", role: .destructive) {
                                viewModel.deleteGame(game, context: modelContext)
                            }
                        }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
    }

    // MARK: - Empty States

    /// Shown when the library has no games at all.
    private var emptyLibraryState: some View {
        ContentUnavailableView {
            Label("No Games in Library", systemImage: "books.vertical")
        } description: {
            Text("Scan your gaming platforms to import your library.")
        } actions: {
            Button("Scan Library") {
                viewModel.scanLibrary(context: modelContext)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.accentColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Shown when search/filter yields no results.
    private var noResultsState: some View {
        ContentUnavailableView.search(text: viewModel.searchText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    LibraryView()
}
