import Contacts
import EventKit
import MediaPlayer
import MultipeerConnectivity
import SwiftUI
import UIKit

@main
struct KalpanaDrivePhoneApp: App {
    @StateObject private var model = PhoneCompanionViewModel()

    var body: some Scene {
        WindowGroup {
            CompanionRootView(model: model)
        }
    }
}

@MainActor
final class PhoneCompanionViewModel: ObservableObject {
    @Published private(set) var lastSyncMessage: String?
    @Published var locationSharingEnabled = false

    let contactsService = ContactsService()
    let musicService = AppleMusicService()
    let locationService = PhoneLocationService()
    let calendarService = CalendarDestinationService()
    let healthService = PhoneHealthService()
    let connection = NearbyPhoneConnection()

    private var heartbeatTask: Task<Void, Never>?

    init() {
        connection.onEnvelope = { [weak self] envelope in
            self?.handle(envelope)
        }
        startHeartbeat()
    }

    deinit {
        heartbeatTask?.cancel()
    }

    func connect(to peer: MCPeerID) {
        connection.connect(to: peer)
    }

    func enableContacts() async {
        await contactsService.requestAndLoad()
        guard contactsService.authorizationStatus == .authorized else {
            lastSyncMessage = contactsService.lastError
            return
        }
        sendContacts()
    }

    func enableAppleMusic() async {
        await musicService.requestAuthorization()
        sendMediaState()
    }

    func enableCalendar() async {
        await calendarService.requestAndLoad()
        sendCalendarDestinations()
    }

    func setLocationSharing(_ enabled: Bool) {
        locationSharingEnabled = enabled
        locationService.setSharingEnabled(enabled)
        if enabled {
            sendLocation()
        }
    }

    func syncAllAvailableData() {
        sendHello()
        sendApprovedData()
    }

    private func sendApprovedData() {
        sendDeviceState()
        if contactsService.authorizationStatus == .authorized {
            sendContacts()
        }
        if musicService.authorizationStatus == .authorized {
            sendMediaState()
        }
        if calendarService.authorizationStatus == .fullAccess {
            sendCalendarDestinations()
        }
        if locationSharingEnabled {
            sendLocation()
        }
    }

    private func sendHello() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let hello = DeviceHello(
            name: UIDevice.current.name,
            platform: "iPhone",
            appVersion: version,
            capabilities: ["contacts", "appleMusic", "calendarDestinations", "location", "deviceHealth"]
        )
        send(.deviceHello, payload: hello)
    }

    private func sendDeviceState() {
        healthService.refresh()
        send(.deviceState, payload: healthService.state)
    }

    private func sendContacts() {
        send(.contactsSnapshot, payload: contactsService.contacts)
    }

    private func sendMediaState() {
        musicService.refresh()
        send(.mediaState, payload: musicService.state)
    }

    private func sendCalendarDestinations() {
        send(.calendarDestinations, payload: calendarService.destinations)
    }

    private func sendLocation() {
        guard let location = locationService.state else { return }
        send(.locationState, payload: location)
    }

    private func send<T: Encodable>(_ type: MessageType, payload: T) {
        do {
            try connection.send(type, payload: payload)
            lastSyncMessage = "Sent \(type.rawValue)"
        } catch {
            lastSyncMessage = error.localizedDescription
        }
    }

    private func handle(_ envelope: CompanionEnvelope) {
        guard envelope.version == 1 else {
            let error = CompanionErrorPayload(
                code: "unsupportedVersion",
                message: "Unsupported protocol version \(envelope.version)."
            )
            send(.error, payload: error)
            return
        }

        switch envelope.type {
        case .mediaCommand:
            handleMediaCommand(envelope)
        case .deviceHello:
            sendApprovedData()
        default:
            break
        }
    }

    private func handleMediaCommand(_ envelope: CompanionEnvelope) {
        do {
            let request = try envelope.decodePayload(MediaCommandRequest.self)
            let result = musicService.execute(request.command)
            send(.mediaCommandResult, payload: result)
            sendMediaState()
        } catch {
            let payload = CompanionErrorPayload(code: "invalidMediaCommand", message: error.localizedDescription)
            send(.error, payload: payload)
        }
    }

    private func startHeartbeat() {
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self, self.connection.connectedPeer != nil else { continue }
                self.healthService.refresh()
                self.send(.heartbeat, payload: self.healthService.state)
                if self.musicService.authorizationStatus == .authorized {
                    self.sendMediaState()
                }
                if self.locationSharingEnabled {
                    self.sendLocation()
                }
            }
        }
    }
}

struct CompanionRootView: View {
    @ObservedObject var model: PhoneCompanionViewModel

    var body: some View {
        NavigationStack {
            List {
                ConnectionSection(model: model, connection: model.connection)
                ContactsSection(model: model, service: model.contactsService)
                MusicPermissionSection(model: model, service: model.musicService)
                LocationSection(model: model, service: model.locationService)
                CalendarSection(model: model, service: model.calendarService)
                CallsLimitationSection()
                if let message = model.lastSyncMessage {
                    Section("Last operation") {
                        Text(message)
                    }
                }
            }
            .navigationTitle("Kalpana Drive Phone")
        }
    }
}

private struct ConnectionSection: View {
    @ObservedObject var model: PhoneCompanionViewModel
    @ObservedObject var connection: NearbyPhoneConnection

    var body: some View {
        Section("Nearby iPad") {
            Text(connection.statusText)
            if let peer = connection.connectedPeer {
                LabeledContent("Connected", value: peer.displayName)
                Button("Sync now") {
                    model.syncAllAvailableData()
                }
            } else if connection.discoveredPeers.isEmpty {
                Text("Open Kalpana Drive on the iPad and keep Wi-Fi and Bluetooth enabled on both devices.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(connection.discoveredPeers, id: \.self) { peer in
                    Button("Connect to \(peer.displayName)") {
                        model.connect(to: peer)
                    }
                }
            }
            if let error = connection.lastError {
                Text(error).foregroundStyle(.red)
            }
        }
    }
}

private struct ContactsSection: View {
    @ObservedObject var model: PhoneCompanionViewModel
    @ObservedObject var service: ContactsService

    var body: some View {
        Section("Contacts") {
            LabeledContent("Permission", value: contactsStatus)
            LabeledContent("Available contacts", value: String(service.contacts.count))
            Button("Allow contacts and sync") {
                Task {
                    await model.enableContacts()
                }
            }
            if let error = service.lastError {
                Text(error).foregroundStyle(.red)
            }
        }
    }

    private var contactsStatus: String {
        switch service.authorizationStatus {
        case .authorized: "Allowed"
        case .denied: "Denied"
        case .restricted: "Restricted"
        case .notDetermined: "Not requested"
        @unknown default: "Unknown"
        }
    }
}

private struct MusicPermissionSection: View {
    @ObservedObject var model: PhoneCompanionViewModel
    @ObservedObject var service: AppleMusicService

    var body: some View {
        Section("Apple Music on this iPhone") {
            LabeledContent("Permission", value: musicStatus)
            LabeledContent("Track", value: service.state.title ?? "Nothing playing")
            LabeledContent("Artist", value: service.state.artist ?? "Unavailable")
            Button("Allow Apple Music and sync") {
                Task {
                    await model.enableAppleMusic()
                }
            }
            Text("This controls the iPhone Apple Music system player. iOS does not expose arbitrary Spotify or YouTube Music sessions to Kalpana Drive.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var musicStatus: String {
        switch service.authorizationStatus {
        case .authorized: "Allowed"
        case .denied: "Denied"
        case .restricted: "Restricted"
        case .notDetermined: "Not requested"
        @unknown default: "Unknown"
        }
    }
}

private struct LocationSection: View {
    @ObservedObject var model: PhoneCompanionViewModel
    @ObservedObject var service: PhoneLocationService

    var body: some View {
        Section("Location") {
            Toggle(
                "Share location with paired iPad",
                isOn: Binding(
                    get: { model.locationSharingEnabled },
                    set: { enabled in model.setLocationSharing(enabled) }
                )
            )
            Text("Location is shared only while this option is enabled and the companion is connected.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let error = service.lastError {
                Text(error).foregroundStyle(.red)
            }
        }
    }
}

private struct CalendarSection: View {
    @ObservedObject var model: PhoneCompanionViewModel
    @ObservedObject var service: CalendarDestinationService

    var body: some View {
        Section("Calendar destinations") {
            LabeledContent("Permission", value: calendarStatus)
            LabeledContent("Upcoming locations", value: String(service.destinations.count))
            Button("Allow calendar and sync destinations") {
                Task {
                    await model.enableCalendar()
                }
            }
            if let error = service.lastError {
                Text(error).foregroundStyle(.red)
            }
        }
    }

    private var calendarStatus: String {
        switch service.authorizationStatus {
        case .fullAccess: "Allowed"
        case .writeOnly: "Write only"
        case .denied: "Denied"
        case .restricted: "Restricted"
        case .notDetermined: "Not requested"
        @unknown default: "Unknown"
        }
    }
}

private struct CallsLimitationSection: View {
    var body: some View {
        Section("Calls") {
            Text("Kalpana Drive can share contacts and request an outgoing call. Apple does not provide a public API for this companion to answer, reject, or inspect native cellular calls. Incoming calls remain in Apple’s Phone/Continuity interface.")
                .foregroundStyle(.secondary)
        }
    }
}
