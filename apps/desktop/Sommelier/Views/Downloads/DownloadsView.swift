import SwiftUI
import SwiftData

struct DownloadsView: View {
    @Query(filter: #Predicate<Game> { game in
        game.statusRawValue == "downloading"
    }) var downloadingGames: [Game]

    var body: some View {
        VStack(spacing: 0) {
            if downloadingGames.isEmpty {
                ContentUnavailableView(
                    "No Active Downloads",
                    systemImage: "arrow.down.circle",
                    description: Text("Games you download will appear here.")
                )
            } else {
                List {
                    ForEach(downloadingGames) { game in
                        DownloadRow(game: game)
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Downloads")
    }
}

struct DownloadRow: View {
    let game: Game
    @State private var progress: Double = 0.5 // Mock progress for now
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon
            if let iconPath = game.iconPath, let nsImage = NSImage(contentsOfFile: iconPath) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 48, height: 48)
                    .cornerRadius(8)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 48, height: 48)
                    Image(systemName: game.platformType.systemImage)
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(game.name)
                    .font(.headline)
                
                HStack(spacing: 12) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: .infinity)
                    
                    Text("\(Int(progress * 100))%")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
                
                HStack {
                    Text("Downloading…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    // Mock network/disk info as requested
                    Text("Network: 45 MB/s  •  Disk: 60 MB/s  •  Time left: 2m 15s")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
    }
}
