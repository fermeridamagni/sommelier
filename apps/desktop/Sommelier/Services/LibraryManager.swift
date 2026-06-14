import AppKit
import Foundation
import OSLog
import SwiftData

/// Logger for library scan operations — helps diagnose why games
/// from specific platforms fail to appear in the library.
private let scanLogger = Logger(subsystem: "com.sommelier.app", category: "LibraryManager")

/// Discovers and imports games from all supported platforms into the SwiftData store.
///
/// Each platform has a different discovery mechanism:
/// - **Epic**: `legendary list-games --json` outputs a JSON array of owned games
/// - **Steam**: The Steam Web API (`IPlayerService/GetOwnedGames`) returns owned games
/// - **Amazon**: `nile library list` outputs owned Amazon Games titles
/// - **Native macOS**: Scans `/Applications` for `.app` bundles
///
/// This class is `@Observable` so the UI can show scanning progress and status.
@MainActor
@Observable
final class LibraryManager {
    // MARK: - Observable State

    /// Whether a library scan is currently in progress.
    var isScanning: Bool = false

    /// A human-readable progress message (e.g. "Scanning Epic Games...").
    var scanProgress: String = ""

    // MARK: - Dependencies

    /// The process runner for CLI tool invocations.
    private let processRunner: ProcessRunner

    /// The auth manager for checking platform authentication before scanning.
    private let authManager: AuthManager

    /// Creates a new `LibraryManager` with the given dependencies.
    ///
    /// - Parameters:
    ///   - processRunner: The runner for subprocess execution. Defaults to shared.
    ///   - authManager: The auth manager for platform status. Defaults to a new instance.
    init(
        processRunner: ProcessRunner = .shared,
        authManager: AuthManager? = nil
    ) {
        self.processRunner = processRunner
        self.authManager = authManager ?? AuthManager()
    }

    // MARK: - Full Scan

    /// Scans all supported platforms and inserts discovered games into SwiftData.
    ///
    /// Games that already exist in the context (matched by name + platform) are
    /// skipped to avoid duplicates. The scan is sequential across platforms but
    /// individual platform scans may run CLI tools concurrently.
    ///
    /// - Parameter context: The SwiftData model context to insert games into.
    @MainActor
    func scanAllPlatforms(context: ModelContext) async {
        isScanning = true
        defer { isScanning = false }

        // Fetch existing games to avoid duplicates.
        let existingGames: [Game]
        do {
            let descriptor = FetchDescriptor<Game>()
            existingGames = (try? context.fetch(descriptor)) ?? []
        }
        let existingNames = Set(existingGames.map { "\($0.name)_\($0.platformRawValue)" })

        // Scan Epic Games.
        scanProgress = "Scanning Epic Games..."
        if let epicGames = try? await scanEpicGames() {
            for game in epicGames where !existingNames.contains("\(game.name)_\(game.platformRawValue)") {
                context.insert(game)
            }
        }

        // Scan Steam Games.
        scanProgress = "Scanning Steam..."
        let settings = AppSettings.load()
        if let apiKey = settings.steamWebAPIKey, let steamID = settings.steamID {
            if let steamGames = try? await scanSteamGames(apiKey: apiKey, steamID: steamID) {
                for game in steamGames where !existingNames.contains("\(game.name)_\(game.platformRawValue)") {
                    context.insert(game)
                }
            }
        }

        // Scan Amazon Games.
        scanProgress = "Scanning Amazon Games..."
        if let amazonGames = try? await scanAmazonGames() {
            for game in amazonGames where !existingNames.contains("\(game.name)_\(game.platformRawValue)") {
                context.insert(game)
            }
        }

        // Scan native macOS apps is disabled by default to avoid cluttering the library
        // with non-game applications. Users can add macOS games manually.

        scanProgress = "Scan complete."
    }

    // MARK: - Epic Games (Legendary)

    /// Scans for owned Epic Games using the `legendary` CLI.
    ///
    /// Runs `legendary list-games --json` which outputs a JSON array of game
    /// objects. Each object contains `app_name`, `app_title`, and metadata.
    /// DLC entries are filtered out by checking `metadata.mainGameItemList`.
    ///
    /// - Returns: An array of `Game` models for discovered Epic games.
    /// - Throws: `ProcessError` if `legendary` is not installed.
    func scanEpicGames() async throws -> [Game] {
        let result = try await processRunner.run(
            command: "legendary",
            arguments: ["list-games", "--json"]
        )

        guard result.exitCode == 0 else {
            scanLogger.warning("legendary list-games exited with code \(result.exitCode): \(result.stderr)")
            return []
        }

        // Extract only the JSON array part in case there's logging printed to stdout
        guard let startRange = result.stdout.range(of: "["),
              let data = String(result.stdout[startRange.lowerBound...]).data(using: .utf8) else {
            scanLogger.warning("legendary list-games returned empty or invalid output")
            return []
        }

        // Decode structure matching actual legendary JSON output.
        // Top-level keys: app_name, app_title, asset_infos, base_urls, dlcs, metadata
        struct LegendaryGame: Decodable {
            let app_name: String
            let app_title: String?

            struct AssetInfo: Decodable {
                let app_name: String?
                let build_version: String?
            }

            /// Platform-keyed asset info (e.g. "Windows", "Mac").
            let asset_infos: [String: AssetInfo]?

            struct Metadata: Decodable {
                struct Category: Decodable {
                    let path: String?
                }
                struct MainGameItem: Decodable {
                    let id: String?
                }
                struct KeyImage: Decodable {
                    let type: String?
                    let url: String?
                }

                let categories: [Category]?
                /// Non-empty for DLC items — contains references to the parent game.
                let mainGameItemList: [MainGameItem]?
                let keyImages: [KeyImage]?
                let title: String?
            }

            let metadata: Metadata?
            let dlcs: [DLCRef]?

            struct DLCRef: Decodable {
                let app_name: String?
            }

            /// Whether this item is a DLC (has a parent game reference).
            var isDLC: Bool {
                guard let mainGameItems = metadata?.mainGameItemList else { return false }
                return !mainGameItems.isEmpty
            }

            /// The display title, preferring `app_title` over metadata title.
            var displayTitle: String {
                app_title ?? metadata?.title ?? app_name
            }
        }

        let legendaryGames: [LegendaryGame]
        do {
            legendaryGames = try JSONDecoder().decode([LegendaryGame].self, from: data)
        } catch {
            scanLogger.error("Failed to decode legendary JSON: \(String(describing: error))")
            return []
        }

        scanLogger.info("Legendary returned \(legendaryGames.count) items")

        return legendaryGames
            .filter { !$0.isDLC } // Exclude DLC entries from the library
            .map { lg in
                Game(
                    name: lg.displayTitle,
                    platform: .epic,
                    executablePath: "",
                    epicAppName: lg.app_name,
                    isInstalled: false
                )
            }
    }

    // MARK: - Steam (Web API)

    /// Scans for owned Steam games using the Steam Web API.
    ///
    /// Calls `IPlayerService/GetOwnedGames/v1` with `include_appinfo=true`
    /// to get game names along with App IDs. Requires a valid Steam Web API
    /// key and the user's Steam 64-bit ID.
    ///
    /// - Parameters:
    ///   - apiKey: Steam Web API key.
    ///   - steamID: The user's Steam 64-bit ID.
    /// - Returns: An array of `Game` models for discovered Steam games.
    /// - Throws: URL/network errors or decoding failures.
    func scanSteamGames(apiKey: String, steamID: String) async throws -> [Game] {
        let urlString = "https://api.steampowered.com/IPlayerService/GetOwnedGames/v1/"
            + "?key=\(apiKey)"
            + "&steamid=\(steamID)"
            + "&include_appinfo=true"
            + "&include_played_free_games=true"
            + "&format=json"

        guard let url = URL(string: urlString) else { return [] }

        let (data, _) = try await URLSession.shared.data(from: url)

        struct SteamResponse: Decodable {
            struct Response: Decodable {
                struct Game: Decodable {
                    let appid: Int
                    let name: String?
                    let playtime_forever: Int? // minutes
                    let img_icon_url: String?
                }
                let games: [Game]?
            }
            let response: Response
        }

        let steamResponse = try JSONDecoder().decode(SteamResponse.self, from: data)

        return (steamResponse.response.games ?? []).compactMap { sg -> Game? in
            guard let name = sg.name, !name.isEmpty else { return nil }
            return Game(
                name: name,
                platform: .steam,
                executablePath: "",
                steamAppID: sg.appid,
                totalPlayTime: TimeInterval((sg.playtime_forever ?? 0) * 60),
                isInstalled: false
            )
        }
    }

    // MARK: - Amazon Games (Nile)

    /// Scans for owned Amazon Games using the `nile` CLI.
    ///
    /// Runs `nile library list` and parses the text output. Nile outputs
    /// one game per line in the format `Title (product_id)`.
    ///
    /// - Returns: An array of `Game` models for discovered Amazon games.
    /// - Throws: `ProcessError` if `nile` is not installed.
    func scanAmazonGames() async throws -> [Game] {
        let result = try await processRunner.run(
            command: "nile",
            arguments: ["library", "list"]
        )

        guard result.exitCode == 0, !result.stdout.isEmpty else { return [] }

        // Parse line-by-line output.
        let lines = result.stdout.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        return lines.compactMap { line -> Game? in
            // Nile outputs lines like "Game Title (amzn1.adg.product.xxx)"
            // Extract the title and ID.
            guard let parenRange = line.range(of: " (", options: .backwards) else {
                // No parenthesized ID — use the whole line as the title.
                return Game(
                    name: line,
                    platform: .amazon,
                    executablePath: "",
                    isInstalled: false
                )
            }

            let title = String(line[line.startIndex..<parenRange.lowerBound])
            var amazonID = String(line[parenRange.upperBound...])
            // Remove trailing ')' if present.
            if amazonID.hasSuffix(")") {
                amazonID = String(amazonID.dropLast())
            }

            guard !title.isEmpty else { return nil }

            return Game(
                name: title,
                platform: .amazon,
                executablePath: "",
                amazonGameID: amazonID,
                isInstalled: false
            )
        }
    }

    // MARK: - Native macOS Apps

    /// Scans directories for native macOS `.app` bundles.
    ///
    /// By default scans `/Applications` and `~/Applications`. Only includes
    /// bundles that have a valid `CFBundleName` in their Info.plist.
    ///
    /// - Parameter directories: Directories to scan. Defaults to
    ///   `/Applications` and `~/Applications`.
    /// - Returns: An array of `Game` models for discovered macOS apps.
    /// - Throws: File system errors during directory enumeration.
    func scanNativeMacApps(
        directories: [URL]? = nil
    ) async throws -> [Game] {
        let searchDirs = directories ?? [
            URL(fileURLWithPath: "/Applications"),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications"),
        ]

        var games: [Game] = []
        let fileManager = FileManager.default

        for directory in searchDirs {
            guard fileManager.fileExists(atPath: directory.path) else { continue }

            guard let enumerator = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            // Collect all .app URLs synchronously (NSDirectoryEnumerator
            // isn't safe to iterate in async contexts in Swift 6).
            var appURLs: [URL] = []
            while let fileURL = enumerator.nextObject() as? URL {
                if fileURL.pathExtension == "app" {
                    appURLs.append(fileURL)
                }
            }

            for fileURL in appURLs {

                // Read the app's Info.plist to get its display name.
                let plistURL = fileURL
                    .appendingPathComponent("Contents")
                    .appendingPathComponent("Info.plist")

                guard let plistData = try? Data(contentsOf: plistURL),
                      let plist = try? PropertyListSerialization.propertyList(
                          from: plistData,
                          options: [],
                          format: nil
                      ) as? [String: Any] else { continue }

                let name = (plist["CFBundleDisplayName"] as? String)
                    ?? (plist["CFBundleName"] as? String)
                    ?? fileURL.deletingPathExtension().lastPathComponent

                // Skip system apps and utilities that aren't games.
                let bundleID = plist["CFBundleIdentifier"] as? String ?? ""
                if bundleID.hasPrefix("com.apple.") { continue }

                let game = Game(
                    name: name,
                    platform: .macNative,
                    executablePath: fileURL.path,
                    installPath: fileURL.path,
                    isNative: true,
                    isInstalled: true
                )
                games.append(game)
            }
        }

        return games
    }
}
