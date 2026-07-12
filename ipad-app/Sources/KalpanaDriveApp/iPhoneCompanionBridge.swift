import Foundation
@preconcurrency import MultipeerConnectivity
import UIKit

struct PhoneBridgeEnvelope: Codable, Sendable {
    let version: Int
    let id: UUID
    let type: PhoneBridgeMessageType
    let deviceID: UUID
    let timestamp: Date
    let sequence: UInt64
    let payload: Data

    init<T: Encodable>(type: PhoneBridgeMessageType, deviceID: UUID, sequence: UInt64, payload: T) throws {
        version = 1
        id = UUID()
        self.type = type
        self.deviceID = deviceID
        timestamp = Date()
        self.sequence = sequence
        self.payload = try JSONEncoder.phoneBridge.encode(payload)
    }

    func decodePayload<T: Decodable>(_ type: T.Type) throws -> T {
        try JSONDecoder.phoneBridge.decode(type, from: payload)
    }
}

enum PhoneBridgeMessageType: String, Codable, Sendable {
    case deviceHello = "device.hello"
    case deviceState = "device.state"
    case contactsSnapshot = "contacts.snapshot"
    case mediaState = "media.state"
    case mediaCommand = "media.command"
    case mediaCommandResult = "media.commandResult"
    case locationState = "location.state"
    case calendarDestinations = "calendar.destinations"
    case heartbeat
    case error
}

struct PhoneBridgeDeviceHello: Codable, Sendable {
    let name: String
    let platform: String
    let appVersion: String
    let capabilities: [String]
}

struct PhoneBridgeDeviceState: Codable, Sendable {
    let batteryPercent: Int?
    let isCharging: Bool
    let isOnline: Bool
    let updatedAt: Date
}

struct PhoneBridgeContact: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let phoneNumbers: [String]
}

struct PhoneBridgeMediaState: Codable, Equatable, Sendable {
    let title: String?
    let artist: String?
    let album: String?
    let isPlaying: Bool
    let elapsed: TimeInterval
    let duration: TimeInterval
    let updatedAt: Date

    static let unavailable = PhoneBridgeMediaState(
        title: nil,
        artist: nil,
        album: nil,
        isPlaying: false,
        elapsed: 0,
        duration: 0,
        updatedAt: Date()
    )
}

enum PhoneBridgeMediaCommand: String, Codable, Sendable {
    case play
    case pause
    case previous
    case next
}

struct PhoneBridgeMediaCommandRequest: Codable, Sendable {
    let command: PhoneBridgeMediaCommand
}

struct PhoneBridgeMediaCommandResult: Codable, Sendable {
    let command: PhoneBridgeMediaCommand
    let succeeded: Bool
    let message: String
}

struct PhoneBridgeLocation: Codable, Sendable {
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double
    let timestamp: Date
}

struct PhoneBridgeCalendarDestination: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let location: String
    let startDate: Date
}

struct PhoneBridgeError: Codable, Sendable {
    let code: String
    let message: String
}

extension JSONEncoder {
    static var phoneBridge: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var phoneBridge: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}

private final class InvitationDecision: @unchecked Sendable {
    let handler: (Bool, MCSession?) -> Void
    init(_ handler: @escaping (Bool, MCSession?) -> Void) { self.handler = handler }
}

@MainActor
final class iPhoneCompanionBridge: NSObject, ObservableObject {
    @Published private(set) var connectedPeer: MCPeerID?
    @Published private(set) var pendingPeer: MCPeerID?
    @Published private(set) var statusText = "Waiting for iPhone companion"
    @Published private(set) var deviceHello: PhoneBridgeDeviceHello?
    @Published private(set) var deviceState: PhoneBridgeDeviceState?
    @Published private(set) var contacts: [PhoneBridgeContact] = []
    @Published private(set) var mediaState: PhoneBridgeMediaState = .unavailable
    @Published private(set) var sharedLocation: PhoneBridgeLocation?
    @Published private(set) var calendarDestinations: [PhoneBridgeCalendarDestination] = []
    @Published private(set) var lastCommandResult: PhoneBridgeMediaCommandResult?
    @Published private(set) var lastError: String?

    private let serviceType = "kalpana-drive"
    private let localPeer = MCPeerID(displayName: "Kalpana Drive iPad")
    private lazy var session = MCSession(peer: localPeer, securityIdentity: nil, encryptionPreference: .required)
    private lazy var advertiser = MCNearbyServiceAdvertiser(
        peer: localPeer,
        discoveryInfo: ["role": "ipad", "protocol": "1"],
        serviceType: serviceType
    )
    private var pendingInvitation: InvitationDecision?
    private var sequence: UInt64 = 0
    private var highestReceivedSequence: UInt64 = 0
    private let deviceID: UUID

    override init() {
        let key = "kalpana.ipad.device-id"
        if let stored = UserDefaults.standard.string(forKey: key), let value = UUID(uuidString: stored) {
            deviceID = value
        } else {
            let value = UUID()
            UserDefaults.standard.set(value.uuidString, forKey: key)
            deviceID = value
        }
        super.init()
        session.delegate = self
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
    }

    deinit {
        advertiser.stopAdvertisingPeer()
        session.disconnect()
    }

    func approvePendingConnection() {
        guard let pendingInvitation else { return }
        pendingInvitation.handler(true, session)
        self.pendingInvitation = nil
        statusText = "Connecting to \(pendingPeer?.displayName ?? "iPhone")"
    }

    func rejectPendingConnection() {
        pendingInvitation?.handler(false, nil)
        pendingInvitation = nil
        pendingPeer = nil
        statusText = "Connection rejected"
    }

    func disconnect() {
        session.disconnect()
        connectedPeer = nil
        contacts = []
        mediaState = .unavailable
        deviceHello = nil
        deviceState = nil
        calendarDestinations = []
        sharedLocation = nil
        lastCommandResult = nil
        statusText = "Waiting for iPhone companion"
    }

    func sendMediaCommand(_ command: PhoneBridgeMediaCommand) {
        send(.mediaCommand, payload: PhoneBridgeMediaCommandRequest(command: command))
    }

    func requestFullSync() {
        sendHello()
    }

    func clearError() {
        lastError = nil
    }

    private func sendHello() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        send(.deviceHello, payload: PhoneBridgeDeviceHello(
            name: UIDevice.current.name,
            platform: "iPad",
            appVersion: version,
            capabilities: ["contactDisplay", "appleMusicRemote", "destinationImport", "locationDisplay"]
        ))
    }

    private func send<T: Encodable>(_ type: PhoneBridgeMessageType, payload: T) {
        guard !session.connectedPeers.isEmpty else {
            lastError = "No iPhone companion is connected."
            return
        }
        do {
            sequence &+= 1
            let envelope = try PhoneBridgeEnvelope(type: type, deviceID: deviceID, sequence: sequence, payload: payload)
            let data = try JSONEncoder.phoneBridge.encode(envelope)
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func receive(_ data: Data) {
        do {
            let envelope = try JSONDecoder.phoneBridge.decode(PhoneBridgeEnvelope.self, from: data)
            guard envelope.version == 1 else {
                lastError = "The iPhone companion uses an unsupported protocol version."
                return
            }
            guard envelope.sequence > highestReceivedSequence else {
                lastError = "A replayed or out-of-order iPhone message was rejected."
                return
            }
            highestReceivedSequence = envelope.sequence
            switch envelope.type {
            case .deviceHello:
                deviceHello = try envelope.decodePayload(PhoneBridgeDeviceHello.self)
                statusText = "Connected to \(deviceHello?.name ?? "iPhone")"
            case .deviceState, .heartbeat:
                deviceState = try envelope.decodePayload(PhoneBridgeDeviceState.self)
            case .contactsSnapshot:
                contacts = try envelope.decodePayload([PhoneBridgeContact].self)
                    .filter { !$0.displayName.isEmpty && !$0.phoneNumbers.isEmpty }
                    .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            case .mediaState:
                mediaState = try envelope.decodePayload(PhoneBridgeMediaState.self)
            case .mediaCommandResult:
                let result = try envelope.decodePayload(PhoneBridgeMediaCommandResult.self)
                lastCommandResult = result
                if !result.succeeded { lastError = result.message }
            case .locationState:
                sharedLocation = try envelope.decodePayload(PhoneBridgeLocation.self)
            case .calendarDestinations:
                calendarDestinations = try envelope.decodePayload([PhoneBridgeCalendarDestination].self)
            case .error:
                lastError = try envelope.decodePayload(PhoneBridgeError.self).message
            case .mediaCommand:
                break
            }
        } catch {
            lastError = "Invalid iPhone companion message: \(error.localizedDescription)"
        }
    }
}

extension iPhoneCompanionBridge: @preconcurrency MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        let decision = InvitationDecision(invitationHandler)
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.pendingInvitation?.handler(false, nil)
            self.pendingPeer = peerID
            self.pendingInvitation = decision
            self.statusText = "Approve connection from \(peerID.displayName)"
        }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor [weak self] in
            self?.lastError = error.localizedDescription
            self?.statusText = "iPhone discovery is unavailable"
        }
    }
}

extension iPhoneCompanionBridge: @preconcurrency MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch state {
            case .connected:
                self.connectedPeer = peerID
                self.pendingPeer = nil
                self.pendingInvitation = nil
                self.highestReceivedSequence = 0
                self.statusText = "Encrypted connection active with \(peerID.displayName)"
                self.sendHello()
            case .connecting:
                self.statusText = "Connecting to \(peerID.displayName)"
            case .notConnected:
                if self.connectedPeer == peerID { self.connectedPeer = nil }
                self.statusText = "Waiting for iPhone companion"
            @unknown default:
                self.statusText = "Unknown companion connection state"
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
