import SwiftUI

struct CompanionDashboardView: View {
    @ObservedObject var model: CompanionModel
    @ObservedObject private var nearby: NearbyIPadService

    init(model: CompanionModel) {
        self.model = model
        nearby = model.nearby
    }

    var body: some View {
        NavigationStack {
            List {
                if let error = model.errorMessage ?? nearby.lastError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                Section("This iPhone") {
                    LabeledContent("Battery", value: model.battery)
                    LabeledContent("Network", value: model.network)
                    LabeledContent("Location permission", value: model.locationPermission)
                    if model.locationPermission == "Not requested" {
                        Button("Allow location sharing", action: model.requestLocation)
                    }
                }

                Section("Nearby iPad") {
                    LabeledContent("Connection", value: nearby.state.rawValue)
                    if let name = nearby.connectedPeerName {
                        LabeledContent("Connected device", value: name)
                        Button("Disconnect", role: .destructive, action: nearby.disconnect)
                    } else if nearby.discoveredPeers.isEmpty {
                        Text("No advertising Kalpana Drive iPad is currently visible on the local network.")
                    } else {
                        ForEach(nearby.discoveredPeers, id: \.self) { peer in
                            Button("Connect to \(peer.displayName)") { nearby.connect(to: peer) }
                        }
                    }
                    Text("Multipeer transport requires encryption. Trusted-device identity approval and revocation will be added before notification or private-data sync is enabled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Share destination") {
                    TextField("Place or address", text: $model.query)
                        .submitLabel(.search)
                        .onSubmit(model.search)
                    Button(model.isSearching ? "Searching…" : "Search", action: model.search)
                        .disabled(model.isSearching)
                    ForEach(model.searchResults) { result in
                        Button { model.share(result) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.name).font(.headline)
                                Text(result.address).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Kalpana Drive")
        }
    }
}
