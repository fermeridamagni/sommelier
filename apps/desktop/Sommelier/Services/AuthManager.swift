import Foundation
import SwiftUI
import OSLog

let authLogger = Logger(subsystem: "com.sommelier.app", category: "AuthManager")

/// Represents the authentication state for a game platform.
enum AuthStatus: Sendable, Equatable {
    /// Authentication status hasn't been checked yet.
    case unknown

    /// The user is authenticated with this platform.
    case authenticated

    /// The user is not authenticated with this platform.
    case notAuthenticated

    /// Authentication is currently in progress.
    case authenticating

    /// An error occurred during authentication.
    case error(String)

    /// Display-friendly label for the current auth state.
    var label: String {
        switch self {
        case .unknown: "Unknown"
        case .authenticated: "Connected"
        case .notAuthenticated: "Not Connected"
        case .authenticating: "Connecting…"
        case .error(let msg): "Error: \(msg)"
        }
    }

    /// Status indicator color for SwiftUI views.
    var color: Color {
        switch self {
        case .unknown: .secondary
        case .authenticated: .green
        case .notAuthenticated: .secondary
        case .authenticating: .blue
        case .error: .red
        }
    }

    /// SF Symbol name for the connection state indicator.
    var systemImage: String {
        switch self {
        case .unknown: "questionmark.circle"
        case .authenticated: "checkmark.circle.fill"
        case .notAuthenticated: "circle"
        case .authenticating: "arrow.triangle.2.circlepath"
        case .error: "exclamationmark.circle.fill"
        }
    }
}

/// Manages authentication with external game platforms (Epic, Steam, Amazon).
///
/// Each platform uses a different CLI tool for authentication:
/// - **Epic**: `legendary auth` (opens browser for OAuth)
/// - **Steam**: `steamcmd +login <username>` (interactive, needs password/2FA via stdin)
/// - **Amazon**: `nile auth --login` (opens browser for OAuth)
///
/// This class is `@Observable` so SwiftUI views can reactively display
/// auth status indicators.
@MainActor
@Observable
final class AuthManager {
    // MARK: - Published Status Properties

    /// Current authentication status for Epic Games Store.
    var epicStatus: AuthStatus = .unknown

    /// Current authentication status for Steam.
    var steamStatus: AuthStatus = .unknown

    /// Current authentication status for Amazon Games.
    var amazonStatus: AuthStatus = .unknown

    // MARK: - Dependencies

    /// The process runner for executing CLI auth commands.
    private let processRunner: ProcessRunner

    /// Creates a new `AuthManager` with the given process runner.
    ///
    /// - Parameter processRunner: The runner for subprocess execution.
    ///   Defaults to the shared singleton.
    init(processRunner: ProcessRunner = .shared) {
        self.processRunner = processRunner
    }

    // MARK: - Epic Games (Legendary)

    /// Retrieves the Epic Games OAuth URL by initiating `legendary auth` silently.
    ///
    /// - Returns: The Epic Games login URL.
    func getEpicLoginURL() async throws -> URL {
        return URL(string: "https://legendary.gl/epiclogin")!
    }

    /// Submits the authorization code to authenticate with Epic Games.
    ///
    /// - Parameter code: The authorization code intercepted from the web view.
    /// - Throws: `ProcessError` if auth fails.
    func loginEpic(code: String) async throws {
        epicStatus = .authenticating
        authLogger.info("Starting loginEpic with code: \(code, privacy: .private)")
        do {
            // Ensure any stale or existing credentials are removed first.
            // If the user is already signed in, legendary ignores --code and keeps the old account.
            // This is identical to Mythic's sign-out-first approach.
            _ = try? await processRunner.run(
                command: "legendary",
                arguments: ["auth", "--delete"]
            )
            
            let result = try await processRunner.run(
                command: "legendary",
                arguments: ["auth", "--code", code]
            )
            authLogger.info("legendary auth exited with code \(result.exitCode)")
            authLogger.info("stdout: \(result.stdout)")
            authLogger.info("stderr: \(result.stderr)")
            
            if result.stderr.contains("ERROR:") || result.stdout.contains("ERROR:") {
                epicStatus = .error("Authentication failed. Please try again.")
            } else if result.stdout.contains("Successfully logged in") || result.stderr.contains("Successfully logged in") || result.exitCode == 0 {
                epicStatus = .authenticated
            } else {
                epicStatus = .error("Authentication failed: \(result.stderr)")
            }
        } catch {
            authLogger.error("Error executing legendary auth: \(error.localizedDescription)")
            epicStatus = .error(error.localizedDescription)
            throw error
        }
    }

    /// Submits Steam credentials obtained from the web view.
    ///
    /// Saves the `steamID` and `steamWebAPIKey` to `UserDefaults`
    /// so that `AppSettings.load()` picks them up for the library scanner.
    ///
    /// - Parameters:
    ///   - steamID: The user's 64-bit Steam ID.
    ///   - apiKey: The generated Steam Web API Key.
    func submitSteamCredentials(steamID: String, apiKey: String) async {
        steamStatus = .authenticating
        
        let defaults = UserDefaults.standard
        defaults.set(steamID, forKey: "steamID")
        defaults.set(apiKey, forKey: "steamWebAPIKey")
        
        // Also force a save to the JSON settings so they stay in sync
        var settings = AppSettings.load()
        settings.steamID = steamID
        settings.steamWebAPIKey = apiKey
        try? settings.save()
        
        steamStatus = .authenticated
    }

    /// Initiates Amazon Games authentication via the `nile` CLI.
    ///
    /// Runs `nile auth --login` which outputs a URL for Amazon's OAuth flow.
    /// We parse this URL, open it, and when nile asks for the redirected URL, we fire `onPrompt`.
    ///
    /// - Parameters:
    ///   - stdinPipe: The pipe used to write the URL back to the process.
    ///   - onPrompt: Called when the process asks for the code/URL.
    /// - Throws: `ProcessError` if `nile` is not installed or auth fails.
    func loginAmazon(stdinPipe: Pipe, onPrompt: @escaping @Sendable () -> Void) async throws {
        amazonStatus = .authenticating
        do {
            let result = try await processRunner.run(
                command: "nile",
                arguments: ["auth", "--login"],
                stdinPipe: stdinPipe,
                onStdout: { line in
                    // Nile outputs "Login URL: https://..."
                    if line.contains("https://"), let urlRange = line.range(of: "(?i)https?://[A-Za-z0-9\\-\\._~:/?#\\[\\]@!$&'()*+,;=%]+", options: .regularExpression) {
                        if let url = URL(string: String(line[urlRange])) {
                            DispatchQueue.main.async { NSWorkspace.shared.open(url) }
                        }
                    }
                    
                    // Nile prompts "Press ENTER to proceed" then "Paste amazon.com url you got redirected to:"
                    if line.contains("Press ENTER") {
                        // Automatically press enter
                        let enter = "\n".data(using: .utf8)!
                        try? stdinPipe.fileHandleForWriting.write(contentsOf: enter)
                    } else if line.contains("Paste amazon.com") || line.contains("redirected to:") {
                        onPrompt()
                    }
                }
            )
            if result.exitCode == 0 {
                amazonStatus = .authenticated
            } else {
                amazonStatus = .error("Authentication failed: \(result.stderr)")
            }
        } catch {
            amazonStatus = .error(error.localizedDescription)
            throw error
        }
    }

    // MARK: - Status Checks

    /// Checks whether the user is currently authenticated with Epic Games.
    ///
    /// Runs `legendary status` and parses the output for login indicators.
    /// Updates `epicStatus` reactively.
    func checkEpicAuth() async {
        epicStatus = .unknown
        do {
            let result = try await processRunner.run(
                command: "legendary",
                arguments: ["status"]
            )
            let output = result.stdout.lowercased()
            // `legendary status` prints "Epic account: <not logged in>" when not authenticated.
            // When authenticated, it prints "Epic account: <username>".
            if output.contains("<not logged in>") {
                epicStatus = .notAuthenticated
            } else if output.contains("epic account:") {
                epicStatus = .authenticated
            } else {
                epicStatus = .notAuthenticated
            }
        } catch {
            // If legendary isn't installed, that's not an auth error —
            // the user just doesn't have the tool.
            epicStatus = .notAuthenticated
        }
    }

    /// Checks whether Steam credentials exist on this system.
    ///
    /// Instead of using `steamcmd`, we simply check if a `steamWebAPIKey`
    /// and `steamID` are configured in the settings.
    func checkSteamAuth() async {
        let settings = AppSettings.load()
        if let key = settings.steamWebAPIKey, !key.isEmpty,
           let id = settings.steamID, !id.isEmpty {
            steamStatus = .authenticated
        } else {
            steamStatus = .notAuthenticated
        }
    }

    /// Checks whether the user is currently authenticated with Amazon Games.
    ///
    /// Runs `nile auth --check` or checks for existing config files.
    /// Updates `amazonStatus` reactively.
    func checkAmazonAuth() async {
        amazonStatus = .unknown
        do {
            let result = try await processRunner.run(
                command: "nile",
                arguments: ["auth", "--status"]
            )
            // nile auth --status outputs JSON like: {"Username": "<not logged in>", "LoggedIn": false}
            if result.stdout.contains("\"LoggedIn\": true") || result.stdout.contains("\"LoggedIn\":true") {
                amazonStatus = .authenticated
            } else {
                amazonStatus = .notAuthenticated
            }
        } catch {
            // Fallback: check for nile's config file.
            let homeDir = FileManager.default.homeDirectoryForCurrentUser
            let nileConfigPath = homeDir
                .appendingPathComponent(".config/nile")
                .appendingPathComponent("user.json")

            if FileManager.default.fileExists(atPath: nileConfigPath.path) {
                amazonStatus = .authenticated
            } else {
                amazonStatus = .notAuthenticated
            }
        }
    }

    /// Refreshes the authentication status for all supported platforms.
    ///
    /// Runs all checks concurrently for faster UI updates during
    /// the login flow or settings screen.
    func refreshAllStatuses() async {
        async let epic: Void = checkEpicAuth()
        async let steam: Void = checkSteamAuth()
        async let amazon: Void = checkAmazonAuth()

        // Await all concurrently — order doesn't matter.
        _ = await (epic, steam, amazon)
    }
}
