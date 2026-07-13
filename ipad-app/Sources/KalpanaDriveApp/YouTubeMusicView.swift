import Combine
import SwiftUI
import UIKit
import WebKit

struct YouTubeMusicView: View {
    @StateObject private var browser = YouTubeMusicBrowserController()
    @State private var showHelp = false

    var body: some View {
        VStack(spacing: 12) {
            browserToolbar

            ZStack {
                YouTubeMusicWebView(controller: browser)

                if browser.isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Loading YouTube Music…")
                            .font(.headline)
                    }
                    .padding(24)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                if let errorMessage = browser.errorMessage {
                    VStack(spacing: 14) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 40, weight: .bold))
                        Text("YouTube Music could not load")
                            .font(.title2.bold())
                        Text(errorMessage)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 620)
                        HStack(spacing: 12) {
                            Button("Retry") {
                                browser.reloadFromHome()
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Open standard YouTube") {
                                browser.loadStandardYouTubeFallback()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(28)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.8), lineWidth: 2)
            )
        }
        .alert("YouTube Music on iPad", isPresented: $showHelp) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Kalpana Drive requests the desktop YouTube Music website inside a persistent WebKit session. Playback remains on this iPad and can route to the Ignis stereo over Bluetooth. Google sign-in and playback must still be verified on the physical iPad.")
        }
    }

    private var browserToolbar: some View {
        HStack(spacing: 12) {
            Label("YouTube Music", systemImage: "play.rectangle.fill")
                .font(.title2.bold())

            Spacer()

            Button {
                browser.goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.bordered)
            .disabled(!browser.canGoBack)
            .accessibilityLabel("Back")

            Button {
                browser.goForward()
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.bordered)
            .disabled(!browser.canGoForward)
            .accessibilityLabel("Forward")

            Button {
                browser.reloadFromHome()
            } label: {
                Image(systemName: "house.fill")
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("YouTube Music home")

            Button {
                browser.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Reload")

            Button {
                showHelp = true
            } label: {
                Image(systemName: "questionmark.circle")
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("YouTube Music help")
        }
    }
}

private struct YouTubeMusicWebView: UIViewRepresentable {
    @ObservedObject var controller: YouTubeMusicBrowserController

    func makeUIView(context: Context) -> WKWebView {
        controller.webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}

@MainActor
final class YouTubeMusicBrowserController: NSObject, ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var errorMessage: String?

    let webView: WKWebView

    private var checkedCurrentPage = false

    private static let musicHomeURL = URL(string: "https://music.youtube.com")!
    private static let standardYouTubeURL = URL(string: "https://www.youtube.com/?persist_app=1&app=desktop")!

    // YouTube Music rejects the normal iPad WKWebView user agent as an unsupported
    // mobile browser. Request its supported desktop web experience instead.
    private static let desktopChromeUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
        "AppleWebKit/537.36 (KHTML, like Gecko) " +
        "Chrome/149.0.0.0 Safari/537.36"

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences.preferredContentMode = .desktop

        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.customUserAgent = Self.desktopChromeUserAgent
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.keyboardDismissMode = .interactive

#if DEBUG
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
#endif

        reloadFromHome()
    }

    func reloadFromHome() {
        checkedCurrentPage = false
        errorMessage = nil
        load(Self.musicHomeURL)
    }

    func loadStandardYouTubeFallback() {
        checkedCurrentPage = false
        errorMessage = nil
        load(Self.standardYouTubeURL)
    }

    func reload() {
        checkedCurrentPage = false
        errorMessage = nil
        if webView.url == nil {
            reloadFromHome()
        } else {
            webView.reload()
        }
    }

    func goBack() {
        guard webView.canGoBack else { return }
        webView.goBack()
    }

    func goForward() {
        guard webView.canGoForward else { return }
        webView.goForward()
    }

    private func load(_ url: URL) {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadRevalidatingCacheData
        request.timeoutInterval = 30
        request.setValue("en-IN,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        webView.load(request)
    }

    private func updateNavigationState() {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }

    private func inspectForUnsupportedBrowserPage() {
        guard !checkedCurrentPage else { return }
        checkedCurrentPage = true

        webView.evaluateJavaScript("document.body ? document.body.innerText : ''") { [weak self] result, _ in
            guard let text = result as? String else { return }
            let normalized = text.lowercased()
            let isUnsupportedPage = normalized.contains("not optimised for your browser") ||
                normalized.contains("not optimized for your browser") ||
                normalized.contains("get chrome")

            guard isUnsupportedPage else { return }
            Task { @MainActor in
                self?.errorMessage = "Google rejected the embedded YouTube Music page even in desktop-browser mode. Retry once; if Google continues to block it, use the standard YouTube fallback while we move playback to the official YouTube player integration."
            }
        }
    }
}

extension YouTubeMusicBrowserController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
        errorMessage = nil
        checkedCurrentPage = false
        updateNavigationState()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        updateNavigationState()
        inspectForUnsupportedBrowserPage()
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        isLoading = false
        updateNavigationState()
        errorMessage = error.localizedDescription
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        isLoading = false
        updateNavigationState()
        errorMessage = error.localizedDescription
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        isLoading = false
        errorMessage = "The YouTube Music web process stopped. Reload to restore it."
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else {
            return .cancel
        }

        guard let scheme = url.scheme?.lowercased() else {
            return .cancel
        }

        if scheme == "https" || scheme == "http" || scheme == "about" {
            return .allow
        }

        errorMessage = "This link requires another application and was not opened automatically."
        return .cancel
    }
}

extension YouTubeMusicBrowserController: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil else { return nil }
        webView.load(navigationAction.request)
        return nil
    }
}
