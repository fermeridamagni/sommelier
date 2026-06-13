import SwiftUI

/// Represents the game store or distribution platform a game originates from.
///
/// Each case maps to a specific launcher CLI tool (e.g. `legendary` for Epic,
/// `steamcmd` for Steam, `nile` for Amazon). The `macNative` case is for apps
/// that run without Wine/GPTK, and `windowsApp` covers standalone Windows
/// executables the user has added manually.
enum Platform: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Valve's Steam platform — games managed via `steamcmd` or Steam Web API.
    case steam

    /// Epic Games Store — games managed via the `legendary` CLI.
    case epic

    /// Amazon Games — games managed via the `nile` CLI.
    case amazon

    /// Native macOS applications that don't need Wine/GPTK translation.
    case macNative

    /// Standalone Windows executables added manually by the user.
    case windowsApp

    /// Conformance to `Identifiable` using the raw string value.
    var id: String { rawValue }

    /// A human-readable name suitable for display in the UI.
    var displayName: String {
        switch self {
        case .steam: "Steam"
        case .epic: "Epic Games"
        case .amazon: "Amazon Games"
        case .macNative: "macOS"
        case .windowsApp: "Windows App"
        }
    }

    /// An SF Symbol name representing this platform.
    ///
    /// Uses generic symbols because SF Symbols doesn't include
    /// branded logos — the app can overlay custom icons where needed.
    var systemImage: String {
        switch self {
        case .steam: "gamecontroller.fill"
        case .epic: "bolt.fill"
        case .amazon: "shippingbox.fill"
        case .macNative: "macwindow"
        case .windowsApp: "pc"
        }
    }

    /// A tint color for visual differentiation in lists and badges.
    var color: Color {
        switch self {
        case .steam: .blue
        case .epic: .indigo
        case .amazon: .orange
        case .macNative: .gray
        case .windowsApp: .purple
        }
    }
}
