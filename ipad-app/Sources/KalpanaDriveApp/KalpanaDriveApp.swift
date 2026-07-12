import KalpanaDriveCore
import SwiftUI

@main
struct KalpanaDriveApp: App {
    @StateObject private var model = DashboardViewModel()

    var body: some Scene {
        WindowGroup {
            DashboardView(model: model)
                .preferredColorScheme(model.appearance == .night ? .dark : .light)
        }
    }
}
