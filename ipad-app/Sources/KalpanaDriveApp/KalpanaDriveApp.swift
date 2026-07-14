import KalpanaDriveCore
import SwiftUI

@main
@MainActor
struct KalpanaDriveApp: App {
    @StateObject private var model = DashboardViewModel()

    init() {
        let key = "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"
        _ = KeychainHelper.shared.saveApiKey(key)
        KeychainHelper.shared.localOnlyMode = false
    }

    var body: some Scene {
        WindowGroup {
            DashboardView(model: model)
                .preferredColorScheme(model.appearance == .night ? .dark : .light)
        }
    }
}
