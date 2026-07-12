import Combine
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
    @Published private(set) var statusMessage = "Preparing companion"
    @Published private(set) var lastSyncMessage: String?
    @Published var locationSharingEnabled = false

    let contactsService = ContactsService()
    let musicService = AppleMusicService()
    let locationService = PhoneLocationService()
    let calendarService = CalendarDestinationService()
    let healthService = PhoneHealthService()
    let connection = NearbyPhoneConnection()

    private var cancellables = Set<AnyCancellable>()
    private var heartbeatTask: Task<Void, Never>?

    init() {
        connection.onEnvelope = { [weak self] envelope in
            self?.handle(envelope)
        }
        Publishers.MergeMany([
            contactsService.objectWillChange.eraseToAnyPublisher(),
            musicService.objectWillChange.eraseToAnyPublisher(),
            locationService.objectWillChange.eraseToAnyPublisher(),
            calendarService.objectWillChange.eraseToAnyPublisher(),
            healthService.objectWillChange.eraseToAnyPublisher(),
            connection.objectWillChange.eraseToAnyPublisher()
        ])
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.objectWillChange.send()
            self?.statusMessage = self?.connection.statusText ?? "Unavailable"
        }
        .store(in: &cancellables)
        startHeartbeat()
    }

    deinit { heartbeatTask?.cancel() }

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
        if enabled { sendLocation() }
    }

    func syncAllAvailableData() {
        sendHello()
        sendApprovedData()
    }

    private func sendApprovedData() {
        sendDeviceState()
        if contactsService.authorizationStatus == .authorized { sendContacts() }
        if musicService.authorizationStatus == .authorized { sendMediaState() }
        if calendarService.authorizationStatus == .fullAccess || calendarService.authorizationStatus == .authorized {
            sendCalendarDestinations()
        }
        if locationSharingEnabled { sendLocation() }
    }

    private func sendHello() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        send(.deviceHello, payload: DeviceHello(
            name: UIDevice.current.name,
            platform: "iPhone",
            appVersion: version,
            capabilities: ["contacts", "appleMusic", "calendarDestinations", "location", "deviceHealth"]
        ))
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
        guard let state = locationService.state else { return }
        send(.locationState, payload: state)
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
            send(.error, payload: CompanionErrorPayload(code: "unsupportedVersion", message: "Unsupported protocol version \(envelope.version)."))
            return
        }
        switch envelope.type {
        case .mediaCommand:
            do {
                let request = try envelope.decodePayload(MediaCommandRequest.self)
                let result = musicService.execute(request.command)
                send(.mediaCommandResult, payload: result)
                sendMediaState()
            } catch {
                send(.error, payload: CompanionErrorPayload(code: "invalidMediaCommand", message: error.localizedDescription))
            }
        case .deviceHello:
            sendApprovedData()
        default:
            break
        }
    }

    private func startHeartbeat() {
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self, self.connection.connectedPeer != nil else { continue }
                self.send(.heartbeat, payload: self.healthService.state)
                self.sendDeviceState()
                if self.musicService.authorizationStatus == .authorized { self.sendMediaState() }
                if self.locationSharingEnabled { self.sendLocation() }
            }
        }
    }
}

struct CompanionRootView: View {
    @ObservedObject var model: PhoneCompanionViewModel

    var body: some View {
        NavigationStack {
            List {
                Section("Nearby iPad") {
                    Text(model.connection.statusText)
                    if let connected = model.connection.connectedPeer {
                        LabeledContent("Connected", value: connected.displayName)
                        Button("Sync now", action: model.syncAllAvailableData)
                    } else if model.connection.discoveredPeers.isEmpty {
                        Text("Open Kalpana Drive on the iPad and keep both devices nearby with Wi-Fi and Bluetooth enabled.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.connection.discoveredPeers, id: \.self) { peer in
                            Button("Connect to \(peer.displayName)") { model.connect(to: peer) }
                        }
                    }
                    if let error = model.connection.lastError {
                        Text(error).foregroundStyle(.red)
                    }
                }

                Section("Contacts") {
                    LabeledContent("Permission", value: contactsStatus)
                    LabeledContent("Available contacts", value: "\(model.contactsService.contacts.count)")
                    Button("Allow contacts and sync") {
                        Task { await model.enableContacts() }
                    }
                }

                Section("Apple Music on this iPhone") {
                    LabeledContent("Permission", value: musicStatus)
                    LabeledContent("Track", value: model.musicService.state.title ?? "Nothing playing")
                    LabeledContent("Artist", value: model.musicService.state.artist ?? "Unavailable")
                    Button("Allow Apple Music and sync") {
                        Task { await model.enableAppleMusic() }
                    }
                    Text("This controls the iPhone Apple Music system player. iOS does not expose arbitrary Spotify or YouTube Music sessions to Kalpana Drive.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Location") {
                    Toggle("Share location with paired iPad", isOn: Binding(
                        get: { model.locationSharingEnabled },
                        set: model.setLocationSharing
                    ))
                    Text("Location is shared only while this option is enabled and the companion is connected.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Calendar destinations") {
                    LabeledContent("Permission", value: calendarStatus)
                    LabeledContent("Upcoming locations", value: "\(model.calendarService.destinations.count)")
                    Button("Allow calendar and sync destinations") {
                        Task { await model.enableCalendar() }
                    }
                }

                Section("Calls") {
                    Text("Kalpana Drive can share contacts and request an outgoing call. Apple does not provide a public API for this companion to answer, reject, or inspect native cellular calls. Incoming calls remain in Apple's Phone/Continuity interface.")
                        .foregroundStyle(.secondary)
                }

                if let message = model.lastSyncMessage {
                    Section("Last operation") { Text(message) }
                }
            }
            .navigationTitle("Kalpana Drive Phone")
        }
    }

    private var contactsStatus: String {
        switch model.contactsService.authorizationStatus {
        case .authorized: "Allowed"
        case .denied: "Denied"
        case .restricted: "Restricted"
        case .notDetermined: "Not requested"
        @unknown default: "Unknown"
        }
    }

    private var musicStatus: String {
        switch model.musicService.authorizationStatus {
        case .authorized: "Allowed"
        case .denied: "Denied"
        case .restricted: "Restricted"
        case .notDetermined: "Not requested"
        @unknown default: "Unknown"
        }
    }

    private var calendarStatus: String {
        switch model.calendarService.authorizationStatus {
        case .fullAccess, .authorized: "Allowed"
        case .writeOnly: "Write only"
        case .denied: "Denied"
        case .restricted: "Restricted"
        case .notDetermined: "Not requested"
        @unknown default: "Unknown"
        }
    }
}
