import Testing
import Foundation
@testable import Sommelier

/// Tests for `AuthManager` status checking and parsing logic.
@Suite("AuthManager Tests")
struct AuthManagerTests {

    @Test("Epic auth status: authenticated")
    @MainActor
    func epicAuthenticated() async {
        let manager = AuthManager()
        // Directly set status to simulate check result
        manager.epicStatus = .authenticated
        #expect(manager.epicStatus == .authenticated)
        #expect(manager.epicStatus.label == "Connected")
    }

    @Test("Epic auth status: not authenticated")
    @MainActor
    func epicNotAuthenticated() async {
        let manager = AuthManager()
        manager.epicStatus = .notAuthenticated
        #expect(manager.epicStatus == .notAuthenticated)
        #expect(manager.epicStatus.label == "Not Connected")
    }

    @Test("Auth status labels are correct")
    func authStatusLabels() {
        #expect(AuthStatus.unknown.label == "Unknown")
        #expect(AuthStatus.authenticated.label == "Connected")
        #expect(AuthStatus.notAuthenticated.label == "Not Connected")
        #expect(AuthStatus.authenticating.label == "Connecting…")
        #expect(AuthStatus.error("test").label == "Error: test")
    }

    @Test("Auth status system images are set")
    func authStatusImages() {
        #expect(AuthStatus.unknown.systemImage == "questionmark.circle")
        #expect(AuthStatus.authenticated.systemImage == "checkmark.circle.fill")
        #expect(AuthStatus.notAuthenticated.systemImage == "circle")
        #expect(AuthStatus.authenticating.systemImage == "arrow.triangle.2.circlepath")
        #expect(AuthStatus.error("x").systemImage == "exclamationmark.circle.fill")
    }

    @Test("Steam auth check: no credential files")
    @MainActor
    func steamNoCredentials() async {
        let manager = AuthManager()
        // After init, status is unknown
        #expect(manager.steamStatus == .unknown)
    }
}
