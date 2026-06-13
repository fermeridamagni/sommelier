import SwiftUI

/// macOS Settings pane with tabs for General, API Keys, Wine/GPTK,
/// CLI Tools, and About.
///
/// Uses a `TabView` for standard macOS Settings window appearance.
/// Each tab is a Form with grouped sections for related settings.
struct SettingsView: View {

    // MARK: - General Settings

    /// Path to the directory where Wine bottles are stored.
    @AppStorage("bottlesDirectory") private var bottlesDirectory: String = "~/Library/Application Support/Sommelier/Bottles"

    /// User's preferred appearance mode.
    @AppStorage("appearanceMode") private var appearanceMode: String = "system"

    // MARK: - API Keys & Accounts

    /// Authentication view model for platforms.
    @State private var authViewModel = AuthViewModel()

    /// SteamGridDB API key for artwork fetching.
    @AppStorage("steamGridDBKey") private var steamGridDBKey: String = ""

    /// Steam Web API key for library sync.
    @AppStorage("steamWebAPIKey") private var steamWebAPIKey: String = ""

    /// Steam user ID for profile features.
    @AppStorage("steamID") private var steamID: String = ""

    // MARK: - Wine/GPTK

    /// Whether to show the Metal performance HUD overlay.
    @AppStorage("metalHUD") private var metalHUD: Bool = false

    /// Whether to enable Esync for improved threading performance.
    @AppStorage("esyncEnabled") private var esyncEnabled: Bool = true

    /// Default environment variables applied to all Wine bottles.
    @AppStorage("defaultEnvVars") private var defaultEnvVars: String = ""

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            accountsTab
                .tabItem {
                    Label("Accounts", systemImage: "person.crop.circle")
                }

            wineTab
                .tabItem {
                    Label("Wine / GPTK", systemImage: "wineglass")
                }

            cliToolsTab
                .tabItem {
                    Label("CLI Tools", systemImage: "terminal")
                }

            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(minWidth: 520, minHeight: 420)
    }

    // MARK: - General Tab

    /// General application settings: bottles directory and appearance.
    private var generalTab: some View {
        Form {
            Section("Storage") {
                LabeledContent("Bottles Directory") {
                    HStack {
                        Text(bottlesDirectory)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Button("Choose…") {
                            chooseBottlesDirectory()
                        }
                        .controlSize(.small)
                    }
                }
            }

            Section("Appearance") {
                Picker("Theme", selection: $appearanceMode) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
    }

    // MARK: - Accounts Tab

    /// Platform authentication and API key management.
    private var accountsTab: some View {
        Form {
            Section("Platform Accounts") {
                platformAuthRow(
                    name: "Epic Games",
                    status: authViewModel.epicStatus,
                    action: authViewModel.loginEpic
                )
                platformAuthRow(
                    name: "Steam",
                    status: authViewModel.steamStatus,
                    action: authViewModel.loginSteam
                )
                platformAuthRow(
                    name: "Amazon Games",
                    status: authViewModel.amazonStatus,
                    action: authViewModel.loginAmazon
                )
            }

            Section("Steam API (Required for Steam Sync)") {
                SecureField("Web API Key", text: $steamWebAPIKey)
                    .textFieldStyle(.roundedBorder)

                TextField("Steam ID", text: $steamID)
                    .textFieldStyle(.roundedBorder)

                Text("Get a key at [steamcommunity.com/dev/apikey](https://steamcommunity.com/dev/apikey)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Section("SteamGridDB") {
                SecureField("API Key", text: $steamGridDBKey)
                    .textFieldStyle(.roundedBorder)

                Text("Used for artwork. Get a key at [steamgriddb.com](https://www.steamgriddb.com)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Accounts")
        .onAppear {
            authViewModel.refreshStatuses()
        }
        .sheet(isPresented: $authViewModel.showingSteamPrompt) {
            VStack(spacing: 20) {
                Text("Steam Login")
                    .font(.title2).fontWeight(.semibold)
                Text("Enter your Steam username to authenticate.")
                    .font(.subheadline).foregroundStyle(.secondary)
                TextField("Steam Username", text: $authViewModel.steamUsername)
                    .textFieldStyle(.roundedBorder).frame(width: 280)
                HStack(spacing: 12) {
                    Button("Cancel") { authViewModel.showingSteamPrompt = false }.buttonStyle(.plain)
                    Button("Login") {
                        authViewModel.showingSteamPrompt = false
                        authViewModel.loginSteam()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(authViewModel.steamUsername.isEmpty)
                }
            }
            .padding(32).frame(width: 380, height: 260)
        }
        .sheet(isPresented: $authViewModel.showingEpicPrompt) {
            if let url = authViewModel.epicLoginURL {
                VStack(spacing: 0) {
                    ZStack {
                        Text("Sign in to Epic Games")
                            .font(.headline)
                        HStack {
                            Spacer()
                            Button(action: { authViewModel.showingEpicPrompt = false }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                                    .imageScale(.large)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                    .background(Color(NSColor.windowBackgroundColor))
                    
                    LoginWebView(url: url) { code in
                        authViewModel.submitEpicCode(code: code)
                    } onCancel: {
                        authViewModel.showingEpicPrompt = false
                    }
                }
                .frame(width: 480, height: 600)
            } else {
                VStack(spacing: 20) {
                    ProgressView()
                    Text("Fetching Epic Games login...")
                        .foregroundStyle(.secondary)
                    Button("Cancel") { authViewModel.showingEpicPrompt = false }
                }
                .frame(width: 300, height: 200)
            }
        }
        .sheet(isPresented: $authViewModel.showingAmazonPrompt) {
            VStack(spacing: 20) {
                Text("Amazon Games Login")
                    .font(.title2).fontWeight(.semibold)
                Text("Please paste the amazon.com URL you were redirected to.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                TextField("Amazon URL", text: $authViewModel.amazonInput)
                    .textFieldStyle(.roundedBorder).frame(width: 280)
                HStack(spacing: 12) {
                    Button("Cancel") { authViewModel.showingAmazonPrompt = false }.buttonStyle(.plain)
                    Button("Submit") {
                        authViewModel.submitAmazonURL()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(authViewModel.amazonInput.isEmpty)
                }
            }
            .padding(32).frame(width: 380, height: 260)
        }
        .alert("Authentication Error", isPresented: Binding(
            get: { authViewModel.errorMessage != nil },
            set: { if !$0 { authViewModel.errorMessage = nil } }
        )) {
            Button("OK") { authViewModel.errorMessage = nil }
        } message: {
            Text(authViewModel.errorMessage ?? "")
        }
    }

    /// Row for connecting a platform.
    private func platformAuthRow(name: String, status: AuthStatus, action: @escaping () -> Void) -> some View {
        LabeledContent {
            if status == .authenticating {
                ProgressView().controlSize(.small)
            } else if status == .authenticated {
                Text("Connected")
                    .foregroundStyle(.green)
            } else {
                Button("Connect") { action() }
                    .controlSize(.small)
            }
        } label: {
            HStack {
                Image(systemName: status.systemImage)
                    .foregroundStyle(status.color)
                Text(name)
            }
        }
    }

    // MARK: - Wine/GPTK Tab

    /// Wine and Game Porting Toolkit configuration.
    private var wineTab: some View {
        Form {
            Section("Performance") {
                Toggle("Metal Performance HUD", isOn: $metalHUD)
                Toggle("Esync (Improved Threading)", isOn: $esyncEnabled)
            }

            Section("Environment Variables") {
                TextEditor(text: $defaultEnvVars)
                    .font(.system(.caption, design: .monospaced))
                    .frame(height: 100)
                    .border(Color.secondary.opacity(0.2))

                Text("One variable per line in KEY=VALUE format.\nApplied to all Wine bottles by default.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Wine / GPTK")
    }

    // MARK: - CLI Tools Tab

    /// Status and paths for CLI tools (legendary, steamcmd, nile).
    private var cliToolsTab: some View {
        Form {
            Section("Installed Tools") {
                cliToolRow(name: "Legendary", detail: "Epic Games Store CLI", command: "legendary")
                cliToolRow(name: "SteamCMD", detail: "Steam command-line client", command: "steamcmd")
                cliToolRow(name: "Nile", detail: "Amazon Games CLI", command: "nile")
            }

            Section {
                Text("Tools can be installed via Homebrew or pip.\nSommelier will automatically detect them on your PATH.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("CLI Tools")
    }

    /// Row displaying a CLI tool's name, description, and install status.
    private func cliToolRow(name: String, detail: String, command: String) -> some View {
        LabeledContent {
            HStack(spacing: 6) {
                let installed = isCommandAvailable(command)
                Circle()
                    .fill(installed ? .green : .orange)
                    .frame(width: 7, height: 7)
                Text(installed ? "Installed" : "Not Found")
                    .font(.caption)
                    .foregroundStyle(installed ? .green : .orange)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - About Tab

    /// App version, credits, and links.
    private var aboutTab: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "wineglass")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)

            Text("Sommelier")
                .font(.title)
                .fontWeight(.bold)

            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("A premium macOS game library manager.\nPlay Windows games natively with GPTK.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Divider()
                .frame(width: 200)

            Text("Built with SwiftUI & SwiftData")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    /// Opens an NSOpenPanel to select a bottles directory.
    private func chooseBottlesDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a directory for Wine bottles"
        panel.prompt = "Choose"

        if panel.runModal() == .OK, let url = panel.url {
            bottlesDirectory = url.path
        }
    }

    private func isCommandAvailable(_ name: String) -> Bool {
        let fm = FileManager.default
        
        var internalPath = SystemInfoService.binDirectory.appendingPathComponent(name).path
        if name == "steamcmd" {
            internalPath = SystemInfoService.binDirectory
                .appendingPathComponent("steamcmd")
                .appendingPathComponent("steamcmd.sh").path
        }
        
        if fm.fileExists(atPath: internalPath) {
            return true
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

#Preview {
    SettingsView()
}
