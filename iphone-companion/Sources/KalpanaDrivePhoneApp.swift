import SwiftUI

@main
struct KalpanaDrivePhoneApp: App {
    @StateObject private var model = CompanionModel()

    var body: some Scene {
        WindowGroup {
            CompanionDashboardView(model: model)
        }
    }
}

