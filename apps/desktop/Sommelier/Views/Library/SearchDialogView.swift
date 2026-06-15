import SwiftUI
import SwiftData

struct SearchDialogView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allGames: [Game]
    
    @Binding var isPresented: Bool
    @State private var searchText = ""
    
    // Filters matching Library
    @State private var selectedPlatforms: Set<Platform> = []
    @State private var installFilter: InstallFilter = .all
    
    var filteredGames: [Game] {
        allGames.filter { game in
            // Search Text Filter
            let matchesSearch = searchText.isEmpty || game.name.localizedCaseInsensitiveContains(searchText)
            
            // Platform Filter
            let matchesPlatform = selectedPlatforms.isEmpty || selectedPlatforms.contains(game.platformType)
            
            // Install Filter
            let matchesInstall: Bool
            switch installFilter {
            case .all: matchesInstall = true
            case .installed: matchesInstall = game.isInstalled
            case .notInstalled: matchesInstall = !game.isInstalled
            }
            
            return matchesSearch && matchesPlatform && matchesInstall
        }
    }
    
    var body: some View {
        ZStack {
            // Invisible background to capture taps to dismiss
            Color.black.opacity(0.001)
                .onTapGesture {
                    isPresented = false
                }
            
            VStack(spacing: 0) {
                // Search Field
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    
                    TextField("Search games...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.title2)
                }
                .padding()
                
                Divider()
                
                // Filters
                VStack(alignment: .leading, spacing: 12) {
                    // Platforms
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            FilterPill(title: "All", systemImage: "square.grid.2x2", isSelected: selectedPlatforms.isEmpty) {
                                selectedPlatforms.removeAll()
                            }
                            
                            ForEach(Platform.allCases, id: \.self) { platform in
                                FilterPill(title: platform.displayName, systemImage: platform.systemImage, isSelected: selectedPlatforms.contains(platform)) {
                                    if selectedPlatforms.contains(platform) {
                                        selectedPlatforms.remove(platform)
                                    } else {
                                        selectedPlatforms.insert(platform)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    // Installed Status
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            FilterPill(title: "All", systemImage: "square.grid.2x2", isSelected: installFilter == .all) {
                                installFilter = .all
                            }
                            FilterPill(title: "Installed", systemImage: "checkmark.circle", isSelected: installFilter == .installed) {
                                installFilter = .installed
                            }
                            FilterPill(title: "Not Installed", systemImage: "arrow.down.circle", isSelected: installFilter == .notInstalled) {
                                installFilter = .notInstalled
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical, 12)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
                
                Divider()
                
                // Results
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if filteredGames.isEmpty {
                            Text("No results found")
                                .foregroundColor(.secondary)
                                .padding(.top, 40)
                                .padding(.bottom, 20)
                        } else {
                            ForEach(filteredGames) { game in
                                SearchResultRow(game: game)
                                    .onTapGesture {
                                        // Later: Navigate to game details
                                        isPresented = false
                                    }
                            }
                        }
                    }
                }
                .frame(maxHeight: 400)
            }
            .background(.regularMaterial) // Liquid glass effect
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)
            .frame(width: 600)
        }
        .onAppear {
            searchText = ""
        }
    }
}

struct SearchResultRow: View {
    let game: Game
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 12) {
            if let iconPath = game.iconPath, let nsImage = NSImage(contentsOfFile: iconPath) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                    .cornerRadius(6)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 32, height: 32)
                    Image(systemName: game.platformType.systemImage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Text(game.name)
                .font(.body)
            
            Spacer()
            
            if game.isInstalled {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            
            Text(game.platformType.displayName)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.2))
                .cornerRadius(4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isHovered ? Color.accentColor.opacity(0.2) : Color.clear)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
