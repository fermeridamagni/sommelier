import Foundation
import SwiftData

/// A persistent model representing a Wine bottle (WINEPREFIX directory).
///
/// Each bottle is an isolated Windows environment managed by GPTK's `wine64`.
/// A bottle may be associated with a specific game via `gameID`, or shared
/// across multiple games. The `path` property points to the actual WINEPREFIX
/// on disk (e.g. `~/Library/Application Support/Sommelier/Bottles/<UUID>/`).
///
/// Environment variables are serialized as JSON `Data` because SwiftData
/// does not support `[String: String]` dictionary storage natively.
@Model
final class Bottle {
    // MARK: - Identity

    /// Unique identifier for this bottle record.
    @Attribute(.unique) var id: UUID

    /// A user-facing name for this bottle (e.g. "Cyberpunk 2077 Bottle").
    var name: String

    // MARK: - Paths

    /// Absolute path to the WINEPREFIX directory on disk.
    ///
    /// This is the directory Wine uses as its root filesystem, containing
    /// `drive_c/`, registry files, and all installed Windows components.
    var path: String

    /// Absolute path to the `wine64` binary used with this bottle.
    ///
    /// Typically points to the GPTK Homebrew installation, e.g.
    /// `/opt/homebrew/Cellar/game-porting-toolkit/3.0/bin/wine64`.
    var wineBinaryPath: String

    // MARK: - Associations

    /// The UUID of the game this bottle was created for, if any.
    ///
    /// A bottle can exist independently (for shared use), so this is optional.
    var gameID: UUID?

    // MARK: - Configuration

    /// JSON-encoded dictionary of custom environment variables.
    ///
    /// Do not access directly — use the `environmentVariables` computed property.
    var environmentVariablesData: Data?

    /// The Windows version this bottle emulates (e.g. "win10", "win7").
    ///
    /// Passed to Wine via `winecfg` or the `WINEARCH` environment variable
    /// during bottle creation.
    var windowsVersion: String

    // MARK: - Metadata

    /// The date and time this bottle was created.
    var createdAt: Date

    // MARK: - Computed Properties

    /// Type-safe access to the custom environment variables dictionary.
    ///
    /// Encodes to / decodes from the underlying `environmentVariablesData`
    /// JSON blob. Returns an empty dictionary if decoding fails or no data
    /// is stored.
    var environmentVariables: [String: String] {
        get {
            guard let data = environmentVariablesData else { return [:] }
            return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
        }
        set {
            environmentVariablesData = try? JSONEncoder().encode(newValue)
        }
    }

    // MARK: - Initializer

    /// Creates a new `Bottle` with the given configuration.
    ///
    /// - Parameters:
    ///   - id: Unique identifier. Defaults to a new UUID.
    ///   - name: Human-readable name for the bottle.
    ///   - path: Absolute path to the WINEPREFIX directory.
    ///   - wineBinaryPath: Absolute path to the `wine64` binary.
    ///   - gameID: Optional associated game UUID.
    ///   - environmentVariables: Custom environment variables. Defaults to empty.
    ///   - windowsVersion: Windows version to emulate. Defaults to `"win10"`.
    ///   - createdAt: Creation date. Defaults to now.
    init(
        id: UUID = UUID(),
        name: String,
        path: String,
        wineBinaryPath: String,
        gameID: UUID? = nil,
        environmentVariables: [String: String] = [:],
        windowsVersion: String = "win10",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.wineBinaryPath = wineBinaryPath
        self.gameID = gameID
        self.environmentVariablesData = try? JSONEncoder().encode(environmentVariables)
        self.windowsVersion = windowsVersion
        self.createdAt = createdAt
    }
}
