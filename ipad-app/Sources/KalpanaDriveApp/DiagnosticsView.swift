import KalpanaDriveCore
import SwiftUI

struct DiagnosticsView: View {
    @ObservedObject var model: DashboardViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Live system health") {
                    LabeledContent("Driving state", value: model.drivingState.rawValue)
                    LabeledContent("GPS permission", value: model.locationPermission)
                    LabeledContent("GPS accuracy", value: model.locationAccuracy)
                    LabeledContent("Reported speed", value: "\(model.speedKPH) km/h")
                    LabeledContent("Network", value: model.isOnline ? "Online" : "Offline")
                    LabeledContent("Audio route", value: model.audioRoute.rawValue)
                    LabeledContent("Battery", value: model.batteryStatus)
                    LabeledContent("Thermal state", value: model.thermalStatus)
                }

                Section("Phone companion") {
                    LabeledContent("State", value: model.phone.state.rawValue)
                    LabeledContent("Platform", value: model.phone.platform.rawValue)
                    if let name = model.phone.deviceName {
                        LabeledContent("Device", value: name)
                    }
                    Text("No call, message, or notification data is shown unless a real authenticated companion is installed and connected.")
                }

                Section("Media") {
                    LabeledContent("Track", value: model.media.title.isEmpty ? "Nothing playing" : model.media.title)
                    LabeledContent("Artist", value: model.media.artist.isEmpty ? "Unavailable" : model.media.artist)
                    LabeledContent("Playback", value: model.media.isPlaying ? "Playing" : "Paused")
                }

                Section("Appearance") {
                    Picker("Appearance", selection: $model.appearance) {
                        Text("Day").tag(DriveAppearance.day)
                        Text("Night").tag(DriveAppearance.night)
                        Text("High sunlight").tag(DriveAppearance.highSunlight)
                    }
                }

                Section("Privacy") {
                    Text("This screen reports only live device health and capability state. It does not contain notification content, credentials, contacts, or precise coordinates.")
                }
            }
            .navigationTitle("System Health")
            .toolbar {
                Button("Done") { dismiss() }
            }
        }
    }
}
