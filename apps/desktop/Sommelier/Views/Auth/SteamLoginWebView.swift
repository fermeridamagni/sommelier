import SwiftUI
import WebKit
import OSLog

struct SteamLoginWebView: NSViewRepresentable {
    let url: URL
    
    /// Callback invoked when Steam ID and Web API Key are successfully extracted.
    let onSuccess: (String, String) -> Void
    
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
        if webView.url == nil {
            let request = URLRequest(url: url)
            webView.load(request)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: SteamLoginWebView
        private var isExtracting = false

        init(_ parent: SteamLoginWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let url = webView.url else { return }
            
            if url.absoluteString.contains("steamcommunity.com") {
                // Check if user has logged in by checking cookies
                webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                    guard let self = self else { return }
                    
                    if let secureCookie = cookies.first(where: { $0.name == "steamLoginSecure" }) {
                        let steamID = secureCookie.value.components(separatedBy: "%7C")[0]
                        
                        // If we are on the apikey page, extract the key
                        if url.absoluteString.contains("dev/apikey") {
                            guard !self.isExtracting else { return }
                            self.isExtracting = true
                            
                            webView.evaluateJavaScript("document.body.innerText") { result, error in
                                if let text = result as? String, let range = text.range(of: "Key: ") {
                                    let key = String(text[range.upperBound...].prefix(32))
                                    self.parent.onSuccess(steamID, key)
                                } else {
                                    // Try to register an API key automatically
                                    let registerScript = """
                                        var domainInput = document.getElementById('domain');
                                        var agreeCheckbox = document.getElementById('agreeToTerms');
                                        var submitBtn = document.getElementById('Submit');
                                        if (domainInput && agreeCheckbox && submitBtn) {
                                            domainInput.value = 'sommelier.app';
                                            agreeCheckbox.checked = true;
                                            submitBtn.click();
                                        }
                                    """
                                    webView.evaluateJavaScript(registerScript) { _, _ in
                                        // The page will reload after submit, and didFinish will be called again
                                        self.isExtracting = false
                                    }
                                }
                            }
                        } else {
                            // Navigate to the API key page if we aren't there yet
                            let request = URLRequest(url: URL(string: "https://steamcommunity.com/dev/apikey")!)
                            webView.load(request)
                        }
                    }
                }
            }
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            viewModelLogger.error("Steam webview error: \\(error.localizedDescription)")
        }
    }
}
