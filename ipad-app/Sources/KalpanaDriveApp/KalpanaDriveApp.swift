import KalpanaDriveCore
import SwiftUI

@main
@MainActor
struct KalpanaDriveApp: App {
    @StateObject private var model = DashboardViewModel()

    var body: some Scene {
        WindowGroup {
            ZStack {
                DashboardView(model: model)

                MusicPlaybackRetentionView(
                    browser: YouTubeMusicBrowserController.shared,
                    shouldRetain: model.selectedSection != .music
                )
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .preferredColorScheme(model.appearance == .night ? .dark : .light)
        }
    }
}
