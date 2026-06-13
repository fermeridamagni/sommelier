import Foundation
import SwiftData

/// Represents the lifecycle state of a game within the app.
///
/// Persisted as a raw `String` inside the `Game` model since SwiftData
/// cannot store enums natively. The `Game.status` computed property
/// provides type-safe access.
enum GameStatus: String, Codable, Sendable {
    /// The game is idle — not running, downloading, or updating.
    case idle

    /// The game is currently being downloaded from its platform.
    case downloading

    /// The game is being installed (e.g. Wine bottle setup, unpacking).
    case installing

    /// The game process is currently running.
    case running

    /// The game is being updated via its platform's CLI.
    case updating

    /// An error occurred during the last operation.
    case error
}

/// A persistent model representing a game or application managed by Sommelier.
///
/// Each game is tied to a `Platform` and optionally linked to a `Bottle`
/// (Wine prefix) when running through GPTK. Native macOS apps set
/// `isNative = true` and leave `bottleID` nil.
///
/// SwiftData requires primitive-storable properties, so enums like `Platform`
/// and `GameStatus` are stored as raw `String` values with computed property
/// wrappers that encode/decode them.
@Model
final class Game {
    // MARK: - Identity

    /// Unique identifier for this game record.
    @Attribute(.unique) var id: UUID

    /// The display name of the game (e.g. "Cyberpunk 2077").
    var name: String

    // MARK: - Platform

    /// Raw string backing store for the `Platform` enum.
    ///
    /// Do not access directly — use the `platformType` computed property.
    var platformRawValue: String

    /// The distribution platform this game belongs to.
    var platformType: Platform {
        get { Platform(rawValue: platformRawValue) ?? .windowsApp }
        set { platformRawValue = newValue.rawValue }
    }

    // MARK: - Paths

    /// Absolute path to the game's executable (`.app` bundle or `.exe` file).
    var executablePath: String

    /// Optional absolute path to the game's install directory.
    var installPath: String?

    // MARK: - Bottle Association

    /// The UUID of the Wine bottle used to run this game, if any.
    ///
    /// Nil for native macOS apps. Links to a `Bottle` record.
    var bottleID: UUID?

    /// Whether this game runs natively on macOS without Wine/GPTK.
    var isNative: Bool

    // MARK: - Artwork

    /// Local file path to the cached cover/grid image.
    var coverImagePath: String?

    /// Local file path to the cached hero/banner image.
    var heroImagePath: String?

    /// Local file path to the cached icon image.
    var iconPath: String?

    // MARK: - Platform-Specific IDs

    /// Steam application ID, used for API lookups and launching.
    var steamAppID: Int?

    /// Epic Games internal application name (used by `legendary`).
    var epicAppName: String?

    /// Amazon Games internal game identifier (used by `nile`).
    var amazonGameID: String?

    // MARK: - Play Tracking

    /// The date and time the game was last launched, if ever.
    var lastPlayed: Date?

    /// Total accumulated play time in seconds.
    var totalPlayTime: TimeInterval

    // MARK: - Status

    /// Raw string backing store for the `GameStatus` enum.
    ///
    /// Do not access directly — use the `status` computed property.
    var statusRawValue: String

    /// The current lifecycle status of this game.
    var status: GameStatus {
        get { GameStatus(rawValue: statusRawValue) ?? .idle }
        set { statusRawValue = newValue.rawValue }
    }

    // MARK: - Metadata

    /// Whether the game is currently installed on disk.
    var isInstalled: Bool

    /// The date this game was first added to the library.
    var dateAdded: Date

    // MARK: - Initializer

    /// Creates a new `Game` with the given properties.
    ///
    /// - Parameters:
    ///   - id: Unique identifier. Defaults to a new UUID.
    ///   - name: Display name of the game.
    ///   - platform: The distribution platform.
    ///   - executablePath: Path to the game's executable.
    ///   - installPath: Optional install directory path.
    ///   - bottleID: Optional Wine bottle UUID.
    ///   - isNative: Whether the game is a native macOS app.
    ///   - coverImagePath: Optional local cover image path.
    ///   - heroImagePath: Optional local hero image path.
    ///   - iconPath: Optional local icon path.
    ///   - steamAppID: Optional Steam App ID.
    ///   - epicAppName: Optional Epic app name.
    ///   - amazonGameID: Optional Amazon game ID.
    ///   - lastPlayed: Optional last-played date.
    ///   - totalPlayTime: Total seconds played. Defaults to 0.
    ///   - status: Initial game status. Defaults to `.idle`.
    ///   - isInstalled: Whether the game is installed. Defaults to `true`.
    ///   - dateAdded: Date the game was added. Defaults to now.
    init(
        id: UUID = UUID(),
        name: String,
        platform: Platform,
        executablePath: String,
        installPath: String? = nil,
        bottleID: UUID? = nil,
        isNative: Bool = false,
        coverImagePath: String? = nil,
        heroImagePath: String? = nil,
        iconPath: String? = nil,
        steamAppID: Int? = nil,
        epicAppName: String? = nil,
        amazonGameID: String? = nil,
        lastPlayed: Date? = nil,
        totalPlayTime: TimeInterval = 0,
        status: GameStatus = .idle,
        isInstalled: Bool = true,
        dateAdded: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.platformRawValue = platform.rawValue
        self.executablePath = executablePath
        self.installPath = installPath
        self.bottleID = bottleID
        self.isNative = isNative
        self.coverImagePath = coverImagePath
        self.heroImagePath = heroImagePath
        self.iconPath = iconPath
        self.steamAppID = steamAppID
        self.epicAppName = epicAppName
        self.amazonGameID = amazonGameID
        self.lastPlayed = lastPlayed
        self.totalPlayTime = totalPlayTime
        self.statusRawValue = status.rawValue
        self.isInstalled = isInstalled
        self.dateAdded = dateAdded
    }
}
