import Combine
import SafariServices
import SwiftUI
import UIKit
import WebKit

// MARK: - YouTube Music View

struct YouTubeMusicView: View {
    @ObservedObject private var browser = YouTubeMusicBrowserController.shared
    @State private var showHelp = false
    @State private var showSignInSheet = false

    var body: some View {
        VStack(spacing: 0) {
            browserToolbar
                .padding(.bottom, 8)

            ZStack {
                YouTubeMusicWebView(controller: browser)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if browser.isLoading {
                    VStack(spacing: 12) {
                        ProgressView().controlSize(.large)
                        Text("Loading YouTube Music…").font(.headline)
                    }
                    .padding(24)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
                }

                if let errorMessage = browser.errorMessage {
                    errorOverlay(message: errorMessage)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Sign-in sheet — SFSafariViewController presented modally (only valid usage)
        .sheet(isPresented: $showSignInSheet) {
            SafariSignInView(url: YouTubeMusicBrowserController.musicHomeURL)
                .ignoresSafeArea()
        }
        .alert("YouTube Music", isPresented: $showHelp) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("YouTube Music plays in an embedded browser. Google does not allow account sign-in inside third-party app browsers (an Apple/Google platform restriction). Music plays without a Google account. Use the Lock Screen or AirPods controls to play, pause, and skip.")
        }
    }

    @ViewBuilder
    private func errorOverlay(message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(.orange)
            Text("YouTube Music could not load")
                .font(.title2.bold())
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 680)

            HStack(spacing: 12) {
                Button("Retry") { browser.reloadFromHome() }
                    .buttonStyle(.borderedProminent)
                Button("YouTube fallback") { browser.loadStandardYouTubeFallback() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(28)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
    }

    private var browserToolbar: some View {
        HStack(spacing: 10) {
            Label("YouTube Music", systemImage: "play.rectangle.fill")
                .font(.title2.bold())

            Spacer()

            Button {
                browser.goBack()
            } label: {
                Image(systemName: "chevron.left").frame(width: 42, height: 42)
            }
            .buttonStyle(.bordered)
            .disabled(!browser.canGoBack)

            Button {
                browser.goForward()
            } label: {
                Image(systemName: "chevron.right").frame(width: 42, height: 42)
            }
            .buttonStyle(.bordered)
            .disabled(!browser.canGoForward)

            Button {
                browser.reloadFromHome()
            } label: {
                Image(systemName: "house.fill").frame(width: 42, height: 42)
            }
            .buttonStyle(.bordered)

            Button {
                browser.reload()
            } label: {
                Image(systemName: "arrow.clockwise").frame(width: 42, height: 42)
            }
            .buttonStyle(.bordered)

            Button {
                showHelp = true
            } label: {
                Image(systemName: "questionmark.circle").frame(width: 42, height: 42)
            }
            .buttonStyle(.bordered)
        }
    }
}

// MARK: - Safari Sign-In Sheet (modal only — Apple requirement)

/// Presented as a modal sheet. Shares Safari's cookie store so Google sign-in
/// works. Note: cookies do NOT transfer to the embedded WKWebView — this is an
/// Apple/Google platform restriction that cannot be bypassed in any third-party app.
struct SafariSignInView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        config.barCollapsingEnabled = true
        return SFSafariViewController(url: url, configuration: config)
    }

    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}

// Keep old name for any remaining references
typealias SafariView = SafariSignInView

// MARK: - Embedded WKWebView

private struct YouTubeMusicWebView: UIViewRepresentable {
    @ObservedObject var controller: YouTubeMusicBrowserController

    func makeUIView(context: Context) -> WKWebView { controller.webView }
    func updateUIView(_ webView: WKWebView, context: Context) {}
}

// MARK: - Browser Controller

@MainActor
final class YouTubeMusicBrowserController: NSObject, ObservableObject, WKScriptMessageHandler {
    static let shared = YouTubeMusicBrowserController()

    @Published private(set) var isLoading = false
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var authenticationBlocked = false
    @Published private(set) var isUsingYouTubeFallback = false

    @Published var isPlaying = false
    @Published var trackTitle = ""
    @Published var trackArtist = ""
    @Published var trackArtwork = ""
    var isPlayerAvailable: Bool { !trackTitle.isEmpty }

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

        let scriptContent = """
        (function() {
            function checkState() {
                var playButton = document.querySelector('ytmusic-play-button-renderer');
                var titleEl = document.querySelector('yt-formatted-string.title.style-scope.ytmusic-player-bar');
                var artistEl = document.querySelector('span.byline.style-scope.ytmusic-player-bar');
                var artworkEl = document.querySelector('img.image.style-scope.ytmusic-player-bar');
                var isPlaying = false;
                var title = "";
                var artist = "";
                var artwork = "";
                if (playButton) {
                    var label = playButton.getAttribute('aria-label') || '';
                    var state = playButton.getAttribute('state') || '';
                    isPlaying = label.toLowerCase().indexOf('pause') !== -1 || state === 'playing';
                }
                if (titleEl) { title = titleEl.innerText; }
                if (artistEl) { artist = artistEl.innerText; }
                if (artworkEl) { artwork = artworkEl.src; }
                window.webkit.messageHandlers.mediaState.postMessage({
                    isPlaying: isPlaying, title: title, artist: artist, artwork: artwork
                });
            }
            setInterval(checkState, 1000);
        })();
        """
        let userScript = WKUserScript(source: scriptContent, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        configuration.userContentController.addUserScript(userScript)

        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()

        webView.configuration.userContentController.add(self, name: "mediaState")
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.customUserAgent = Self.desktopSafariUserAgent
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never

#if DEBUG
        if #available(iOS 16.4, *) { webView.isInspectable = true }
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
        if webView.url == nil { reloadFromHome() } else { webView.reload() }
    }

    func goBack()    { guard webView.canGoBack    else { return }; webView.goBack() }
    func goForward() { guard webView.canGoForward else { return }; webView.goForward() }

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
            let isAuthError = normalized.contains("disallowed_useragent") ||
                normalized.contains("browser or app may not be secure") ||
                normalized.contains("couldn't sign you in")
            let isUnsupported = normalized.contains("not optimised for your browser") ||
                normalized.contains("not optimized for your browser") ||
                normalized.contains("browser is not supported") ||
                normalized.contains("update your browser") ||
                normalized.contains("get chrome")
            guard isAuthError || isUnsupported else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.authenticationBlocked = isAuthError
                self.errorMessage = isAuthError
                    ? "Google blocks sign-in inside embedded browsers. This is an Apple/Google platform restriction. Music plays without signing in."
                    : "Google rejected this browser. Retry or use YouTube fallback."
            }
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "mediaState", message.frameInfo.isMainFrame else { return }
        guard YouTubeDomainValidator.isTrusted(message.webView?.url) else { return }
        guard let dict = message.body as? [String: Any],
              let data = try? JSONSerialization.data(withJSONObject: dict),
              let state = try? JSONDecoder().decode(WebKitMediaState.self, from: data) else { return }
        guard state.title.count <= 500, state.artist.count <= 500, state.artwork.count <= 2048 else { return }
        if !state.artwork.isEmpty {
            guard let artURL = URL(string: state.artwork),
                  let scheme = artURL.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" || scheme == "data" else { return }
        }
        isPlaying = state.isPlaying
        trackTitle = state.title
        trackArtist = state.artist
        trackArtwork = state.artwork
    }

    func getPlayerState() async -> String {
        guard YouTubeDomainValidator.isTrusted(webView.url) else { return "untrustedDomain" }
        do {
            let result = try await webView.evaluateJavaScript(
                "(function() { var media = document.querySelector('video, audio'); if (!media) return 'unavailable'; return media.paused ? 'paused' : 'playing'; })()"
            )
            return (result as? String) ?? "unavailable"
        } catch { return "error" }
    }

    @discardableResult func play() async -> MusicControlResult {
        guard YouTubeDomainValidator.isTrusted(webView.url) else { return .untrustedDomain }
        let state = await getPlayerState()
        if state == "playing" { return .alreadyInRequestedState }
        do {
            _ = try await webView.evaluateJavaScript("document.querySelector('ytmusic-play-button-renderer').click()")
            return .succeeded
        } catch { return .commandRejected }
    }

    @discardableResult func pause() async -> MusicControlResult {
        guard YouTubeDomainValidator.isTrusted(webView.url) else { return .untrustedDomain }
        let state = await getPlayerState()
        if state == "paused" { return .alreadyInRequestedState }
        do {
            _ = try await webView.evaluateJavaScript("document.querySelector('ytmusic-play-button-renderer').click()")
            return .succeeded
        } catch { return .commandRejected }
    }

    @discardableResult func next() async -> MusicControlResult {
        guard YouTubeDomainValidator.isTrusted(webView.url) else { return .untrustedDomain }
        do {
            _ = try await webView.evaluateJavaScript("document.querySelector('.next-button').click()")
            return .succeeded
        } catch { return .commandRejected }
    }

    @discardableResult func previous() async -> MusicControlResult {
        guard YouTubeDomainValidator.isTrusted(webView.url) else { return .untrustedDomain }
        do {
            _ = try await webView.evaluateJavaScript("document.querySelector('.previous-button').click()")
            return .succeeded
        } catch { return .commandRejected }
    }

    @discardableResult func searchMusic(query: String) async -> MusicControlResult {
        guard YouTubeDomainValidator.isTrusted(webView.url) else { return .untrustedDomain }
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return .commandRejected }
        load(URL(string: "https://music.youtube.com/search?q=\(encoded)")!)
        return .succeeded
    }
}

extension YouTubeMusicBrowserController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true; errorMessage = nil; authenticationBlocked = false
        checkedCurrentPage = false; updateNavigationState()
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false; updateNavigationState(); inspectCurrentPage()
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isLoading = false; updateNavigationState()
        errorMessage = "Could not connect. Check network and retry. (\(error.localizedDescription))"
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isLoading = false; updateNavigationState()
        errorMessage = "Page stopped loading. Retry. (\(error.localizedDescription))"
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        isLoading = false
        errorMessage = "YouTube Music web process stopped. Reload to restore."
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .cancel }
        if url.absoluteString == "about:blank" { return .allow }
        // Block Google sign-in — it cannot work in WKWebView
        if let host = url.host?.lowercased(),
           host == "accounts.google.com" || host.hasSuffix(".accounts.google.com") {
            authenticationBlocked = true
            errorMessage = "Google blocks sign-in inside embedded browsers (an Apple/Google platform restriction). Music plays without signing in."
            return .cancel
        }
        guard YouTubeDomainValidator.isTrusted(url) else { return .cancel }
        return .allow
    }
}

extension YouTubeMusicBrowserController: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil else { return nil }
        webView.load(navigationAction.request)
        return nil
    }
}

// MARK: - Supporting Types

enum YouTubeDomainValidator {
    static func isTrusted(_ url: URL?) -> Bool {
        guard let url, let host = url.host?.lowercased() else { return false }
        
        // Explicitly reject accounts/sign-in
        if host == "accounts.google.com" || host.hasSuffix(".accounts.google.com") {
            return false
        }
        
        return host == "music.youtube.com" ||
               host == "youtube.com" ||
               host == "www.youtube.com" ||
               host.hasSuffix(".youtube.com") ||
               host == "google.com" ||
               host.hasSuffix(".google.com")
    }
}

struct WebKitMediaState: Codable {
    let isPlaying: Bool
    let title: String
    let artist: String
    let artwork: String
}

enum MusicControlResult: String, Codable {
    case succeeded, alreadyInRequestedState, playerUnavailable
    case unsupportedPage, untrustedDomain, commandRejected, verificationFailed
}
