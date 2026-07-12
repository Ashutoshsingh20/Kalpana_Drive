import SwiftUI
import KalpanaDriveCore

@main
struct KalpanaDriveApp: App {
    @StateObject private var model = DashboardViewModel()

    var body: some Scene {
        WindowGroup {
            DashboardView(model: model)
                .preferredColorScheme(model.appearance == .day ? .light : .dark)
        }
    }
}

