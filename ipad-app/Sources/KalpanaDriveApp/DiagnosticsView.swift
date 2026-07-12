import SwiftUI
import KalpanaDriveCore

struct DiagnosticsView: View {
    @ObservedObject var model: DashboardViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("System health") {
                    LabeledContent("Driving state", value: model.drivingState.rawValue)
                    LabeledContent("Phone", value: model.phone.state.rawValue)
                    LabeledContent("Audio route", value: model.audioRoute.rawValue)
                    LabeledContent("Data source", value: "Phase 1 simulation")
                }
                Section("Simulation") {
                    Button("Toggle parked / moving", action: model.toggleSimulation)
                    Picker("Appearance", selection: $model.appearance) {
                        Text("Day").tag(DriveAppearance.day)
                        Text("Night").tag(DriveAppearance.night)
                        Text("High sunlight").tag(DriveAppearance.highSunlight)
                    }
                }
                Section("Privacy") {
                    Text("Diagnostic output contains no notification content, credentials, contacts, or precise location.")
                }
            }
            .navigationTitle("System Health")
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}
