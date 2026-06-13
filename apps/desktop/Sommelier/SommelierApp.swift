import SwiftData
import SwiftUI

/// The main entry point for the Sommelier application.
///
/// Routes between three app states:
/// 1. **Onboarding** — First launch: verifies system dependencies (Rosetta, GPTK, CLI tools)
/// 2. **Login** — Platform authentication (Epic/Steam/Amazon)
/// 3. **Main** — The primary app interface with sidebar navigation
///
/// App state is persisted via `@AppStorage` so users don't repeat onboarding.
@main
struct SommelierApp: App {
    /// Tracks whether the user has completed the first-launch onboarding flow.
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    /// Tracks whether the user has completed (or skipped) platform authentication.
    @AppStorage("hasCompletedAuth") private var hasCompletedAuth = false

    /// SwiftData model container for persisting games, bottles, and settings.
    private let modelContainer: ModelContainer

    init() {
        do {
            let schema = Schema([
                Game.self,
                Bottle.self,
            ])
            let configuration = ModelConfiguration(
                "Sommelier",
                schema: schema,
                isStoredInMemoryOnly: false
            )
            modelContainer = try ModelContainer(
                for: schema,
                configurations: [configuration]
            )
        } catch {
            fatalError("Failed to initialize SwiftData ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if !hasCompletedOnboarding {
                    OnboardingView(onComplete: {
                        hasCompletedOnboarding = true
                    })
                } else if !hasCompletedAuth {
                    LoginView(onComplete: {
                        hasCompletedAuth = true
                    })
                } else {
                    MainView()
                }
            }
            .frame(minWidth: 900, minHeight: 600)
        }
        .modelContainer(modelContainer)
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)

        #if os(macOS)
        Settings {
            SettingsView()
                .modelContainer(modelContainer)
        }
        #endif
    }
}
