import SwiftUI
import WebKit

struct YouTubeMusicView: View {
    @State private var reloadToken = UUID()
    @State private var showHelp = false

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Label("YouTube Music", systemImage: "play.rectangle.fill")
                    .font(.title2.bold())
                Text("Runs directly on this iPad inside Kalpana Drive")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    reloadToken = UUID()
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)

                Button {
                    showHelp = true
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .buttonStyle(.bordered)
            }

            YouTubeMusicWebView(reloadToken: reloadToken)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.8), lineWidth: 2)
                )
        }
        .alert("YouTube Music on iPad", isPresented: $showHelp) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Search and play inside the embedded YouTube Music website. Playback remains on the iPad and can route to the Ignis stereo over Bluetooth. Google may require you to sign in again inside this view.")
        }
    }
}

private struct YouTubeMusicWebView: UIViewRepresentable {
    let reloadToken: UUID

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        context.coordinator.lastReloadToken = reloadToken
        loadHome(in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastReloadToken != reloadToken else { return }
        context.coordinator.lastReloadToken = reloadToken
        loadHome(in: webView)
    }

    private func loadHome(in webView: WKWebView) {
        guard let url = URL(string: "https://music.youtube.com") else { return }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadRevalidatingCacheData
        request.timeoutInterval = 30
        webView.load(request)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastReloadToken: UUID?

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else {
                return .cancel
            }

            if let scheme = url.scheme?.lowercased(), scheme != "https", scheme != "http", scheme != "about" {
                _ = await UIApplication.shared.open(url)
                return .cancel
            }

            return .allow
        }
    }
}
