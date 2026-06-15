import Foundation
import SwiftUI
import OSLog

let viewModelLogger = Logger(subsystem: "com.sommelier.app", category: "AuthViewModel")

// MARK: - AuthViewModel


/// Manages authentication state for all supported gaming platforms.
///
/// Each platform uses its respective CLI tool for authentication:
/// - **Epic Games**: Legendary CLI with browser-based OAuth
/// - **Steam**: SteamCMD with username/password
/// - **Amazon**: Nile CLI with browser-based auth
@MainActor
@Observable
final class AuthViewModel {

    // MARK: Platform Statuses

    /// Epic Games authentication status.
    var epicStatus: AuthStatus { authManager.epicStatus }

    /// Steam authentication status.
    var steamStatus: AuthStatus { authManager.steamStatus }

    /// Amazon Games authentication status.
    var amazonStatus: AuthStatus { authManager.amazonStatus }

    // MARK: - Manager

    private let authManager = AuthManager()

    // MARK: - Auth Flow State

    // Epic Games
    var showingEpicPrompt: Bool = false
    var epicLoginURL: URL?

    // Steam
    let steamLoginURL = URL(string: "https://steamcommunity.com/login/home/?goto=dev%2Fapikey")!
    var showingSteamPrompt: Bool = false

    // Amazon
    var showingAmazonPrompt: Bool = false
    var amazonInput: String = ""
    private var amazonStdinPipe: Pipe?

    // MARK: Error Handling

    /// User-facing error message, shown as an alert.
    var errorMessage: String?

    // MARK: Computed Properties

    /// True if at least one platform is authenticated.
    var hasAnyConnection: Bool {
        epicStatus == .authenticated
            || steamStatus == .authenticated
            || amazonStatus == .authenticated
    }

    /// True if any platform is currently authenticating.
    var isAuthenticating: Bool {
        epicStatus == .authenticating
            || steamStatus == .authenticating
            || amazonStatus == .authenticating
    }

    // MARK: - Methods

    /// Initiates Epic Games login via a web view OAuth flow.
    func loginEpic() {
        Task { @MainActor in
            do {
                epicLoginURL = try await authManager.getEpicLoginURL()
                showingEpicPrompt = true
            } catch {
                errorMessage = "Failed to get Epic Games login URL: \(error.localizedDescription)"
            }
        }
    }

    /// Submits the intercepted Epic Games authorization code.
    func submitEpicCode(code: String) {
        viewModelLogger.info("submitEpicCode called with code length: \(code.count)")
        showingEpicPrompt = false
        Task { @MainActor in
            do {
                try await authManager.loginEpic(code: code)
            } catch {
                viewModelLogger.error("submitEpicCode error: \(error.localizedDescription)")
                errorMessage = "Epic Games login failed: \(error.localizedDescription)"
            }
        }
    }

    /// Initiates Steam login via the Web View flow.
    func loginSteam() {
        showingSteamPrompt = true
    }

    /// Submits the extracted Steam credentials from the web view.
    func submitSteamCredentials(steamID: String, apiKey: String) {
        showingSteamPrompt = false
        Task { @MainActor in
            await authManager.submitSteamCredentials(steamID: steamID, apiKey: apiKey)
        }
    }

    /// Initiates Amazon Games login via Nile's interactive OAuth flow.
    func loginAmazon() {
        let pipe = Pipe()
        self.amazonStdinPipe = pipe
        amazonInput = ""
        
        Task { @MainActor in
            do {
                try await authManager.loginAmazon(
                    stdinPipe: pipe,
                    onPrompt: {
                        Task { @MainActor in
                            self.showingAmazonPrompt = true
                        }
                    }
                )
            } catch {
                errorMessage = "Amazon Games login failed: \(error.localizedDescription)"
            }
            self.amazonStdinPipe = nil
        }
    }

    /// Submits the user-entered Amazon URL back to the nile process.
    func submitAmazonURL() {
        showingAmazonPrompt = false
        let input = amazonInput.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
        if let data = input.data(using: .utf8) {
            try? amazonStdinPipe?.fileHandleForWriting.write(contentsOf: data)
        }
    }

    /// Re-checks authentication status for all platforms by querying their CLI tools.
    func refreshStatuses() {
        Task { @MainActor in
            await authManager.refreshAllStatuses()
        }
    }
}
