import SwiftUI
import WebKit

/// Platform authentication screen displayed after onboarding.
///
/// Shows three glass-effect cards — one per gaming platform — with
/// connection status and login buttons. Users can skip authentication
/// and connect platforms later in Settings.
struct LoginView: View {

    /// Called when the user proceeds (either after connecting or skipping).
    let onComplete: () -> Void

    @State private var viewModel = AuthViewModel()

    var body: some View {
        ZStack {
            // Premium dark gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.06, blue: 0.10),
                    Color(red: 0.12, green: 0.09, blue: 0.14),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // Header
                VStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 48))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.accentColor, Color.accentColor.opacity(0.6)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    Text("Connect Your Platforms")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)

                    Text("Sign in to import your game libraries.")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.7))
                }

                // Platform cards
                HStack(spacing: 20) {
                    platformCard(
                        name: "Epic Games",
                        icon: "e.circle.fill",
                        color: .white,
                        status: viewModel.epicStatus,
                        action: viewModel.loginEpic
                    )

                    platformCard(
                        name: "Steam",
                        icon: "gamecontroller.fill",
                        color: Color(red: 0.10, green: 0.47, blue: 0.71),
                        status: viewModel.steamStatus,
                        action: viewModel.loginSteam
                    )

                    platformCard(
                        name: "Amazon",
                        icon: "a.circle.fill",
                        color: Color(red: 1.0, green: 0.60, blue: 0.0),
                        status: viewModel.amazonStatus,
                        action: viewModel.loginAmazon
                    )
                }
                .padding(.horizontal, 32)

                Spacer()

                // Bottom actions
                VStack(spacing: 16) {
                    Button("Continue") {
                        onComplete()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.accentColor)
                    .controlSize(.large)
                    .disabled(viewModel.isAuthenticating)

                    Button("Skip for now") {
                        onComplete()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.5))
                    .font(.subheadline)
                }
                .padding(.bottom, 32)
            }
        }
        .sheet(isPresented: $viewModel.showingSteamPrompt) {
            steamLoginSheet
        }
        .sheet(isPresented: $viewModel.showingEpicPrompt) {
            if let url = viewModel.epicLoginURL {
                VStack(spacing: 0) {
                    ZStack {
                        Text("Sign in to Epic Games")
                            .font(.headline)
                        HStack {
                            Spacer()
                            Button(action: { viewModel.showingEpicPrompt = false }) {
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
                        viewModel.submitEpicCode(code: code)
                    } onCancel: {
                        viewModel.showingEpicPrompt = false
                    }
                }
                .frame(width: 480, height: 600)
            } else {
                VStack(spacing: 20) {
                    ProgressView()
                    Text("Fetching Epic Games login...")
                        .foregroundStyle(.secondary)
                    Button("Cancel") { viewModel.showingEpicPrompt = false }
                }
                .frame(width: 300, height: 200)
            }
        }
        .alert("Authentication Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .onAppear {
            viewModel.refreshStatuses()
        }
    }

    // MARK: - Platform Card

    /// Glass-effect card showing a platform's connection status and login action.
    private func platformCard(
        name: String,
        icon: String,
        color: Color,
        status: AuthStatus,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(color)

            Text(name)
                .font(.headline)
                .foregroundStyle(.white)

            // Status indicator
            HStack(spacing: 6) {
                Image(systemName: status.systemImage)
                    .font(.caption2)
                    .foregroundStyle(status.color)
                Text(status.label)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer()

            // Action button
            if status == .authenticating {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            } else if status == .authenticated {
                Button("Disconnect") {
                    // In production: log out via CLI
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.red.opacity(0.8))
            } else {
                Button("Connect") {
                    action()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(Color.accentColor)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 220)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Steam Login Sheet

    /// Modal sheet for entering Steam credentials.
    private var steamLoginSheet: some View {
        VStack(spacing: 20) {
            Text("Steam Login")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Enter your Steam username to authenticate via SteamCMD.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("Steam Username", text: $viewModel.steamUsername)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)

            HStack(spacing: 12) {
                Button("Cancel") {
                    viewModel.showingSteamPrompt = false
                }
                .buttonStyle(.plain)

                Button("Login") {
                    viewModel.showingSteamPrompt = false
                    viewModel.loginSteam()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accentColor)
                .disabled(viewModel.steamUsername.isEmpty)
            }
        }
        .padding(32)
        .frame(width: 380, height: 260)
    }
}

#Preview {
    LoginView(onComplete: {})
        .frame(width: 900, height: 600)
}
import SwiftUI
import WebKit

/// A native web view designed to intercept OAuth redirects and JSON responses
/// for platform authentication flows (e.g., Epic Games).
struct LoginWebView: NSViewRepresentable {
    let url: URL
    
    /// Callback invoked when an authorization code is successfully intercepted.
    let onCodeIntercepted: (String) -> Void
    
    /// Callback invoked if the user manually cancels or an error occurs.
    let onCancel: () -> Void

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Use a non-persistent data store to ensure a clean login state
        config.websiteDataStore = .nonPersistent()
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        
        // Custom user agent helps ensure we get the standard login page
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let request = URLRequest(url: url)
        webView.load(request)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: LoginWebView

        init(_ parent: LoginWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Check if the page is the Epic Games redirect API which returns JSON
            guard let currentURL = webView.url else { return }
            
            viewModelLogger.info("WebView didFinish loading URL: \(currentURL.absoluteString, privacy: .public)")
            
            if currentURL.path.contains("/id/api/redirect") {
                // The page should contain JSON with the authorization code
                webView.evaluateJavaScript("document.body.innerText") { [weak self] result, error in
                    guard let self = self else { return }
                    
                    if let error = error {
                        viewModelLogger.error("evaluateJavaScript error: \(error.localizedDescription)")
                        return
                    }
                    
                    guard let jsonString = result as? String else {
                        viewModelLogger.warning("evaluateJavaScript result is not a String")
                        return
                    }
                    
                    viewModelLogger.info("Intercepted JSON string: \(jsonString, privacy: .private)")
                    
                    if let data = jsonString.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let code = json["authorizationCode"] as? String {
                        
                        viewModelLogger.info("Successfully parsed authorizationCode")
                        DispatchQueue.main.async {
                            self.parent.onCodeIntercepted(code)
                        }
                    } else {
                        viewModelLogger.error("Failed to parse JSON or find authorizationCode")
                    }
                }
            }
        }

        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Alternatively, if the redirect URL is caught before loading the JSON:
            if let url = navigationAction.request.url {
                viewModelLogger.info("decidePolicyFor URL: \(url.absoluteString, privacy: .public)")
                if url.host == "localhost",
                   url.path.contains("/launcher/authorized"),
                   let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let code = components.queryItems?.first(where: { $0.name == "code" })?.value {
                    
                    viewModelLogger.info("Intercepted code from localhost redirect in decidePolicyFor")
                    DispatchQueue.main.async {
                        self.parent.onCodeIntercepted(code)
                    }
                    decisionHandler(.cancel)
                    return
                }
            }
            
            decisionHandler(.allow)
        }
    }
}
