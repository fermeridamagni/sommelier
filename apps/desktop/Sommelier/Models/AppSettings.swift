import Foundation

/// User-configurable preferences for the Sommelier application.
///
/// Persisted as a single JSON file in the app's Application Support directory
/// rather than SwiftData, because settings are a simple key-value document
/// that doesn't benefit from a relational store. The file is created on first
/// save and loaded with sensible defaults if missing or corrupt.
struct AppSettings: Codable, Sendable {
    // MARK: - API Keys

    /// SteamGridDB API key for fetching game artwork (covers, heroes, icons).
    ///
    /// Stored here for convenience but the canonical secure copy lives
    /// in Keychain via `KeychainService`. This is a cached plaintext copy
    /// used to avoid Keychain lookups on every API call.
    var steamGridDBAPIKey: String?

    /// Steam Web API key for fetching owned games and player data.
    var steamWebAPIKey: String?

    /// The user's Steam 64-bit ID, used with the Steam Web API.
    var steamID: String?

    // MARK: - Paths

    /// Directory where Wine bottles are stored on disk.
    ///
    /// Defaults to `~/Library/Application Support/Sommelier/Bottles`.
    /// Users can change this to an external drive or custom location.
    var bottlesDirectory: String

    // MARK: - Runtime Options

    /// Whether to overlay Apple's Metal performance HUD during gameplay.
    ///
    /// Sets `MTL_HUD_ENABLED=1` in the Wine process environment.
    var enableMetalHUD: Bool

    /// Whether to enable esync for improved Wine threading performance.
    ///
    /// Sets `WINEESYNC=1` in the Wine process environment. Enabled by
    /// default because macOS supports the required eventfd emulation.
    var enableEsync: Bool

    // MARK: - Defaults

    /// The default bottles directory path, resolved against the user's home.
    private static var defaultBottlesDirectory: String {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport
            .appendingPathComponent("Sommelier", isDirectory: true)
            .appendingPathComponent("Bottles", isDirectory: true)
            .path
    }

    /// Creates settings with sensible defaults for first-time use.
    init(
        steamGridDBAPIKey: String? = nil,
        steamWebAPIKey: String? = nil,
        steamID: String? = nil,
        bottlesDirectory: String? = nil,
        enableMetalHUD: Bool = false,
        enableEsync: Bool = true
    ) {
        self.steamGridDBAPIKey = steamGridDBAPIKey
        self.steamWebAPIKey = steamWebAPIKey
        self.steamID = steamID
        self.bottlesDirectory = bottlesDirectory ?? Self.defaultBottlesDirectory
        self.enableMetalHUD = enableMetalHUD
        self.enableEsync = enableEsync
    }

    // MARK: - Persistence

    /// The URL of the settings JSON file in Application Support.
    private static var fileURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let sommelierDir = appSupport.appendingPathComponent("Sommelier", isDirectory: true)
        return sommelierDir.appendingPathComponent("settings.json")
    }

    /// Loads settings from disk, returning defaults if the file doesn't exist
    /// or is corrupt.
    ///
    /// This is intentionally synchronous because it's called during app
    /// initialization where async isn't practical.
    ///
    /// - Returns: The loaded `AppSettings`, or a default instance.
    static func load() -> AppSettings {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return AppSettings()
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            return try decoder.decode(AppSettings.self, from: data)
        } catch {
            // If the file is corrupt, return defaults rather than crashing.
            // The next save will overwrite the corrupt file.
            return AppSettings()
        }
    }

    /// Saves the current settings to disk as formatted JSON.
    ///
    /// Creates the parent directory if it doesn't exist.
    ///
    /// - Throws: File system errors if the directory can't be created
    ///   or the file can't be written.
    func save() throws {
        let url = Self.fileURL
        let directory = url.deletingLastPathComponent()

        // Ensure the Sommelier directory exists.
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url, options: .atomic)
    }
}
