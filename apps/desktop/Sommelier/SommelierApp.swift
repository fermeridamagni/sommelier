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
            
            let fm = FileManager.default
            let appSupportURL = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let appDirURL = appSupportURL.appendingPathComponent("Sommelier")
            
            if !fm.fileExists(atPath: appDirURL.path) {
                try? fm.createDirectory(at: appDirURL, withIntermediateDirectories: true)
            }
            
            let oldStoreURL = appSupportURL.appendingPathComponent("Sommelier.store")
            let newStoreURL = appDirURL.appendingPathComponent("Sommelier.store")
            
            if fm.fileExists(atPath: oldStoreURL.path) && !fm.fileExists(atPath: newStoreURL.path) {
                let extensions = ["", "-shm", "-wal", ".bak"]
                for ext in extensions {
                    let oldFileURL = appSupportURL.appendingPathComponent("Sommelier.store\(ext)")
                    let newFileURL = appDirURL.appendingPathComponent("Sommelier.store\(ext)")
                    if fm.fileExists(atPath: oldFileURL.path) {
                        try? fm.moveItem(at: oldFileURL, to: newFileURL)
                    }
                }
            }
            
            let configuration = ModelConfiguration(
                schema: schema,
                url: newStoreURL
            )
            modelContainer = try ModelContainer(
                for: schema,
                configurations: [configuration]
            )

            // Reset any stuck running statuses from previous sessions asynchronously
            let container = modelContainer
            Task { @MainActor [container] in
                do {
                    let context = container.mainContext
                    let games = try context.fetch(FetchDescriptor<Game>())
                    var changed = false
                    for game in games {
                        if game.statusRawValue == GameStatus.running.rawValue {
                            game.statusRawValue = GameStatus.idle.rawValue
                            changed = true
                        }
                    }
                    if changed {
                        try context.save()
                    }
                } catch {
                    print("Failed to reset stuck game statuses: \(error)")
                }
            }
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
