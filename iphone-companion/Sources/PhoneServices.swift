import Combine
import Contacts
import CoreLocation
import EventKit
import Foundation
import MediaPlayer
@preconcurrency import MultipeerConnectivity
import Network
import UIKit

@MainActor
final class ContactsService: ObservableObject {
    @Published private(set) var authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
    @Published private(set) var contacts: [ContactRecord] = []
    @Published private(set) var lastError: String?

    private let store = CNContactStore()

    func requestAndLoad() async {
        do {
            if authorizationStatus == .notDetermined {
                _ = try await store.requestAccess(for: .contacts)
                authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
            }
            guard authorizationStatus == .authorized else {
                contacts = []
                lastError = "Contacts permission is required before contacts can be shared with the paired iPad."
                return
            }
            try loadContacts()
        } catch {
            contacts = []
            lastError = error.localizedDescription
        }
    }

    private func loadContacts() throws {
        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.sortOrder = .userDefault
        var loaded: [ContactRecord] = []
        try store.enumerateContacts(with: request) { contact, _ in
            let personalName = [contact.givenName, contact.familyName]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            let displayName = personalName.isEmpty ? contact.organizationName : personalName
            let numbers = contact.phoneNumbers.map(\.value.stringValue).filter { !$0.isEmpty }
            guard !displayName.isEmpty, !numbers.isEmpty else { return }
            loaded.append(ContactRecord(id: contact.identifier, displayName: displayName, phoneNumbers: numbers))
        }
        contacts = loaded
        lastError = nil
    }
}

@MainActor
final class AppleMusicService: ObservableObject {
    @Published private(set) var authorizationStatus = MPMediaLibrary.authorizationStatus()
    @Published private(set) var state: PhoneMediaState = .unavailable
    @Published private(set) var lastError: String?

    private let player = MPMusicPlayerController.systemMusicPlayer
    private var cancellables = Set<AnyCancellable>()

    init() {
        player.beginGeneratingPlaybackNotifications()
        Publishers.Merge(
            NotificationCenter.default.publisher(for: .MPMusicPlayerControllerNowPlayingItemDidChange),
            NotificationCenter.default.publisher(for: .MPMusicPlayerControllerPlaybackStateDidChange)
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in self?.refresh() }
        .store(in: &cancellables)
        refresh()
    }

    func requestAuthorization() async {
        if authorizationStatus == .notDetermined {
            authorizationStatus = await withCheckedContinuation { continuation in
                MPMediaLibrary.requestAuthorization { value in
                    continuation.resume(returning: value)
                }
            }
        }
        refresh()
    }

    func execute(_ command: PhoneMediaCommand) -> MediaCommandResult {
        guard authorizationStatus == .authorized else {
            return MediaCommandResult(
                command: command,
                succeeded: false,
                message: "Apple Music permission is not granted on the iPhone."
            )
        }
        switch command {
        case .play: player.play()
        case .pause: player.pause()
        case .previous: player.skipToPreviousItem()
        case .next: player.skipToNextItem()
        }
        refresh()
        return MediaCommandResult(
            command: command,
            succeeded: true,
            message: "The command was submitted to the iPhone Apple Music system player."
        )
    }

    func refresh() {
        guard authorizationStatus == .authorized, let item = player.nowPlayingItem else {
            state = .unavailable
            return
        }
        state = PhoneMediaState(
            title: item.title,
            artist: item.artist,
            album: item.albumTitle,
            isPlaying: player.playbackState == .playing,
            elapsed: max(0, player.currentPlaybackTime),
            duration: max(0, item.playbackDuration),
            updatedAt: Date()
        )
        lastError = nil
    }
}

@MainActor
final class PhoneLocationService: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var state: SharedLocationState?
    @Published private(set) var lastError: String?

    private let manager = CLLocationManager()

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 50
    }

    func setSharingEnabled(_ enabled: Bool) {
        guard enabled else {
            manager.stopUpdatingLocation()
            state = nil
            return
        }
        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
            manager.startUpdatingLocation()
        } else {
            lastError = "Location permission is required before sharing can start."
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last,
              location.horizontalAccuracy >= 0,
              abs(location.timestamp.timeIntervalSinceNow) <= 30 else { return }
        state = SharedLocationState(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            horizontalAccuracy: location.horizontalAccuracy,
            timestamp: location.timestamp
        )
        lastError = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        lastError = error.localizedDescription
    }
}

@MainActor
final class CalendarDestinationService: ObservableObject {
    @Published private(set) var authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    @Published private(set) var destinations: [CalendarDestination] = []
    @Published private(set) var lastError: String?

    private let store = EKEventStore()

    func requestAndLoad() async {
        do {
            if authorizationStatus == .notDetermined {
                _ = try await store.requestFullAccessToEvents()
                authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            }
            guard authorizationStatus == .fullAccess else {
                destinations = []
                lastError = "Full calendar access is required to share event destinations."
                return
            }
            let start = Date()
            let end = Calendar.current.date(byAdding: .day, value: 14, to: start) ?? start
            let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
            destinations = store.events(matching: predicate)
                .filter { !($0.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .prefix(50)
                .map {
                    CalendarDestination(
                        id: $0.eventIdentifier ?? UUID().uuidString,
                        title: $0.title ?? "Calendar event",
                        location: $0.location ?? "",
                        startDate: $0.startDate
                    )
                }
            lastError = nil
        } catch {
            destinations = []
            lastError = error.localizedDescription
        }
    }
}

@MainActor
final class PhoneHealthService: ObservableObject {
    @Published private(set) var state = PhoneDeviceState(
        batteryPercent: nil,
        isCharging: false,
        isOnline: false,
        updatedAt: Date()
    )

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.kalpana.drive.phone.network")
    private var cancellables = Set<AnyCancellable>()
    private var isOnline = false

    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOnline = path.status == .satisfied
                self?.refresh()
            }
        }
        monitor.start(queue: queue)
        NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)
            .merge(with: NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        refresh()
    }

    func refresh() {
        let level = UIDevice.current.batteryLevel
        state = PhoneDeviceState(
            batteryPercent: level >= 0 ? Int((level * 100).rounded()) : nil,
            isCharging: UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full,
            isOnline: isOnline,
            updatedAt: Date()
        )
    }
}

@MainActor
final class NearbyPhoneConnection: NSObject, ObservableObject {
    @Published private(set) var discoveredPeers: [MCPeerID] = []
    @Published private(set) var connectedPeer: MCPeerID?
    @Published private(set) var statusText = "Searching for Kalpana Drive on a nearby iPad"
    @Published private(set) var lastError: String?

    var onEnvelope: (@MainActor (CompanionEnvelope) -> Void)?

    private let serviceType = "kalpana-drive"
    private let localPeer = MCPeerID(displayName: UIDevice.current.name)
    private lazy var session = MCSession(peer: localPeer, securityIdentity: nil, encryptionPreference: .required)
    private lazy var browser = MCNearbyServiceBrowser(peer: localPeer, serviceType: serviceType)
    private var sequence: UInt64 = 0
    private var highestReceivedSequence: UInt64 = 0

    override init() {
        super.init()
        session.delegate = self
        browser.delegate = self
        browser.startBrowsingForPeers()
    }

    func connect(to peer: MCPeerID) {
        statusText = "Requesting encrypted connection to \(peer.displayName)"
        browser.invitePeer(peer, to: session, withContext: nil, timeout: 20)
    }

    func send<T: Encodable>(_ type: MessageType, payload: T) throws {
        guard !session.connectedPeers.isEmpty else { throw ConnectionError.notConnected }
        sequence &+= 1
        let envelope = try CompanionEnvelope(
            type: type,
            deviceID: DeviceIdentity.shared.id,
            sequence: sequence,
            payload: payload
        )
        let data = try JSONEncoder.companion.encode(envelope)
        try session.send(data, toPeers: session.connectedPeers, with: .reliable)
    }

    private func receive(_ data: Data) {
        do {
            let envelope = try JSONDecoder.companion.decode(CompanionEnvelope.self, from: data)
            guard envelope.sequence > highestReceivedSequence else {
                lastError = "A replayed or out-of-order iPad message was rejected."
                return
            }
            highestReceivedSequence = envelope.sequence
            onEnvelope?(envelope)
        } catch {
            lastError = "Received an invalid companion message: \(error.localizedDescription)"
        }
    }

    enum ConnectionError: LocalizedError {
        case notConnected
        var errorDescription: String? { "No iPad is connected." }
    }
}

extension NearbyPhoneConnection: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(
        _ browser: MCNearbyServiceBrowser,
        foundPeer peerID: MCPeerID,
        withDiscoveryInfo info: [String : String]?
    ) {
        guard info?["role"] == "ipad" else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            if !self.discoveredPeers.contains(peerID) { self.discoveredPeers.append(peerID) }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor [weak self] in
            self?.discoveredPeers.removeAll { $0 == peerID }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor [weak self] in
            self?.lastError = error.localizedDescription
            self?.statusText = "Nearby discovery failed"
        }
    }
}

extension NearbyPhoneConnection: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch state {
            case .connected:
                self.connectedPeer = peerID
                self.highestReceivedSequence = 0
                self.statusText = "Encrypted connection active with \(peerID.displayName)"
            case .connecting:
                self.statusText = "Connecting to \(peerID.displayName)"
            case .notConnected:
                if self.connectedPeer == peerID { self.connectedPeer = nil }
                self.statusText = "Disconnected — searching for iPad"
            @unknown default:
                self.statusText = "Unknown connection state"
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor [weak self] in self?.receive(data) }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

@MainActor
final class DeviceIdentity {
    static let shared = DeviceIdentity()
    let id: UUID

    private init() {
        let key = "kalpana.phone.device-id"
        if let stored = UserDefaults.standard.string(forKey: key), let value = UUID(uuidString: stored) {
            id = value
        } else {
            let value = UUID()
            UserDefaults.standard.set(value.uuidString, forKey: key)
            id = value
        }
    }
}
