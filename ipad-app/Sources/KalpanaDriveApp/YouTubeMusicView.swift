import Combine
import SafariServices
import SwiftUI
import UIKit
import WebKit

struct YouTubeMusicView: View {
    @ObservedObject private var browser = YouTubeMusicBrowserController.shared
    @State private var showHelp = false
    @State private var showSafariFallback = false

    var body: some View {
        VStack(spacing: 12) {
            browserToolbar

            ZStack {
                YouTubeMusicWebView(controller: browser)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

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
                    errorOverlay(message: errorMessage)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.8), lineWidth: 2)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert("YouTube Music on iPad", isPresented: $showHelp) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Guest playback uses one persistent WebKit player that remains mounted when you return to the dashboard. Google does not permit account authentication inside WKWebView, so signed-in YouTube Music opens in Apple's secure in-app Safari browser and does not sign the embedded player in.")
        }
        .sheet(isPresented: $showSafariFallback) {
            SafariView(url: YouTubeMusicBrowserController.musicHomeURL)
                .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private func errorOverlay(message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: browser.authenticationBlocked ? "person.crop.circle.badge.exclamationmark" : "exclamationmark.triangle.fill")
                .font(.system(size: 40, weight: .bold))
            Text(browser.authenticationBlocked ? "Google sign-in requires a secure browser" : "YouTube Music could not load")
                .font(.title2.bold())
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 680)

            HStack(spacing: 12) {
                if browser.authenticationBlocked {
                    Button("Open signed-in browser") {
                        showSafariFallback = true
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Retry") {
                        browser.reloadFromHome()
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button("Use YouTube fallback") {
                    browser.loadStandardYouTubeFallback()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(28)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var browserToolbar: some View {
        HStack(spacing: 12) {
            Label("YouTube Music", systemImage: "play.rectangle.fill")
                .font(.title2.bold())

            if browser.isUsingYouTubeFallback {
                Text("YouTube fallback")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.regularMaterial)
                    .clipShape(Capsule())
            }

            Spacer()

            Button {
                showSafariFallback = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "safari")
                    Text("Secure Sign-in")
                }
                .font(.subheadline.bold())
                .frame(height: 42)
                .padding(.horizontal, 10)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Open signed-in YouTube Music browser")

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

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        configuration.barCollapsingEnabled = false
        return SFSafariViewController(url: url, configuration: configuration)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

private struct YouTubeMusicWebView: UIViewRepresentable {
    @ObservedObject var controller: YouTubeMusicBrowserController

    func makeUIView(context: Context) -> WKWebView {
        MusicWebViewResidence.shared.releaseForVisiblePlayback(controller.webView)
        return controller.webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Void) {
        MusicWebViewResidence.shared.visiblePlayerWasRemoved(uiView)
    }
}

/// The app root keeps this tiny host mounted while another dashboard section is
/// visible. The same WKWebView therefore remains attached to a window and WebKit
/// does not tear down the active media session when MusicSection disappears.
struct MusicPlaybackRetentionView: UIViewRepresentable {
    @ObservedObject var browser: YouTubeMusicBrowserController
    let shouldRetain: Bool

    func makeUIView(context: Context) -> UIView {
        let container = UIView(frame: .zero)
        container.isUserInteractionEnabled = false
        container.clipsToBounds = true
        MusicWebViewResidence.shared.update(
            retentionContainer: container,
            browser: browser,
            shouldRetain: shouldRetain
        )
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        MusicWebViewResidence.shared.update(
            retentionContainer: container,
            browser: browser,
            shouldRetain: shouldRetain
        )
    }
}

@MainActor
private final class MusicWebViewResidence {
    static let shared = MusicWebViewResidence()

    private weak var retentionContainer: UIView?
    private weak var browser: YouTubeMusicBrowserController?
    private var shouldRetain = true
    private var visiblePlayerAttached = false

    func update(
        retentionContainer: UIView,
        browser: YouTubeMusicBrowserController,
        shouldRetain: Bool
    ) {
        self.retentionContainer = retentionContainer
        self.browser = browser
        self.shouldRetain = shouldRetain

        if shouldRetain {
            visiblePlayerAttached = false
            scheduleRetention()
        } else if browser.webView.superview === retentionContainer {
            browser.webView.removeFromSuperview()
        }
    }

    func releaseForVisiblePlayback(_ webView: WKWebView) {
        visiblePlayerAttached = true
        if webView.superview === retentionContainer {
            webView.removeFromSuperview()
        }
    }

    func visiblePlayerWasRemoved(_ webView: WKWebView) {
        visiblePlayerAttached = false
        scheduleRetention()
    }

    private func scheduleRetention() {
        guard shouldRetain else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.shouldRetain,
                  !self.visiblePlayerAttached,
                  let container = self.retentionContainer,
                  let webView = self.browser?.webView else { return }

            if webView.superview !== container {
                webView.removeFromSuperview()
                webView.frame = container.bounds
                webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                container.addSubview(webView)
            }
        }
    }
}

@MainActor
final class YouTubeMusicBrowserController: NSObject, ObservableObject {
    static let shared = YouTubeMusicBrowserController()

    @Published private(set) var isLoading = false
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var authenticationBlocked = false
    @Published private(set) var isUsingYouTubeFallback = false

    let webView: WKWebView

    private var checkedCurrentPage = false

    static let musicHomeURL = URL(string: "https://music.youtube.com/?persist_app=1&app=desktop")!
    private static let standardYouTubeURL = URL(string: "https://www.youtube.com/?persist_app=1&app=desktop")!

    private static let desktopSafariUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
        "AppleWebKit/605.1.15 (KHTML, like Gecko) " +
        "Version/18.5 Safari/605.1.15"

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
        webView.customUserAgent = Self.desktopSafariUserAgent
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
        authenticationBlocked = false
        isUsingYouTubeFallback = false
        load(Self.musicHomeURL)
    }

    func loadStandardYouTubeFallback() {
        checkedCurrentPage = false
        errorMessage = nil
        authenticationBlocked = false
        isUsingYouTubeFallback = true
        load(Self.standardYouTubeURL)
    }

    func reload() {
        checkedCurrentPage = false
        errorMessage = nil
        authenticationBlocked = false
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

    private func inspectCurrentPage() {
        guard !checkedCurrentPage else { return }
        checkedCurrentPage = true

        webView.evaluateJavaScript("document.body ? document.body.innerText : ''") { [weak self] result, _ in
            guard let text = result as? String else { return }
            let normalized = text.lowercased()

            let isAuthenticationError = normalized.contains("disallowed_useragent") ||
                normalized.contains("browser or app may not be secure") ||
                normalized.contains("couldn't sign you in")

            let isUnsupportedPage = normalized.contains("not optimised for your browser") ||
                normalized.contains("not optimized for your browser") ||
                normalized.contains("browser is not supported") ||
                normalized.contains("update your browser") ||
                normalized.contains("get chrome")

            guard isAuthenticationError || isUnsupportedPage else { return }
            Task { @MainActor in
                guard let self else { return }
                self.authenticationBlocked = isAuthenticationError
                if isAuthenticationError {
                    self.errorMessage = "Google blocks account authentication inside embedded WKWebView browsers. Open the signed-in browser for your Google account, or continue with guest playback in the embedded player. The browser login cannot be copied into WebKit."
                } else {
                    self.errorMessage = "Google rejected the embedded YouTube Music browser. Retry desktop mode or use the standard YouTube fallback."
                }
            }
        }
    }
}

extension YouTubeMusicBrowserController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
        errorMessage = nil
        authenticationBlocked = false
        checkedCurrentPage = false
        updateNavigationState()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        updateNavigationState()
        inspectCurrentPage()
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        isLoading = false
        updateNavigationState()
        errorMessage = "The music page could not connect. Check the network and retry. Technical detail: \(error.localizedDescription)"
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        isLoading = false
        updateNavigationState()
        errorMessage = "The music page stopped loading. Retry the page. Technical detail: \(error.localizedDescription)"
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        isLoading = false
        errorMessage = "The YouTube Music web process stopped. Reload to restore it."
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url,
              let scheme = url.scheme?.lowercased() else {
            return .cancel
        }

        if let host = url.host?.lowercased(),
           host == "accounts.google.com" || host.hasSuffix(".accounts.google.com") {
            authenticationBlocked = true
            errorMessage = "Google does not permit account sign-in inside an embedded WKWebView. Use Secure Sign-in for the supported browser path."
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
