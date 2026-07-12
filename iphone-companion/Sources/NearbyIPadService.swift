@preconcurrency import MultipeerConnectivity
import Combine
import Foundation
import UIKit

@MainActor
final class NearbyIPadService: NSObject, ObservableObject, MCNearbyServiceBrowserDelegate, MCSessionDelegate {
    @Published private(set) var state: NearbyConnectionState = .searching
    @Published private(set) var discoveredPeers: [MCPeerID] = []
    @Published private(set) var connectedPeerName: String?
    @Published private(set) var lastError: String?

    private let serviceType = "kalpana-drive"
    private let localPeer = MCPeerID(displayName: UIDevice.current.name)
    private lazy var session = MCSession(peer: localPeer, securityIdentity: nil, encryptionPreference: .required)
    private lazy var browser = MCNearbyServiceBrowser(peer: localPeer, serviceType: serviceType)
    private var sequence: UInt64 = 0
    private let deviceId: UUID

    override init() {
        if let value = UserDefaults.standard.string(forKey: "companionDeviceId"), let stored = UUID(uuidString: value) {
            deviceId = stored
        } else {
            let created = UUID()
            deviceId = created
            UserDefaults.standard.set(created.uuidString, forKey: "companionDeviceId")
        }
        super.init()
        session.delegate = self
        browser.delegate = self
        browser.startBrowsingForPeers()
    }

    func connect(to peer: MCPeerID) {
        guard !session.connectedPeers.contains(peer) else { return }
        state = .inviting
        lastError = nil
        browser.invitePeer(peer, to: session, withContext: nil, timeout: 30)
    }

    func disconnect() {
        session.disconnect()
        connectedPeerName = nil
        state = .searching
    }

    func send(destination: SharedDestinationPayload) throws {
        guard !session.connectedPeers.isEmpty else {
            throw NearbyError.noConnectedIPad
        }
        sequence += 1
        let envelope = CompanionEnvelope(
            version: 1,
            id: UUID(),
            type: "destination.shared",
            deviceId: deviceId,
            timestamp: Int64(Date().timeIntervalSince1970 * 1_000),
            sequence: sequence,
            payload: destination
        )
        let data = try JSONEncoder().encode(envelope)
        try session.send(data, toPeers: session.connectedPeers, with: .reliable)
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            guard !discoveredPeers.contains(peerID) else { return }
            discoveredPeers.append(peerID)
            if state == .disconnected { state = .searching }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in discoveredPeers.removeAll { $0 == peerID } }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in
            state = .failed
            lastError = "Nearby iPad discovery failed: \(error.localizedDescription)"
        }
    }

    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .notConnected:
                connectedPeerName = nil
                self.state = .searching
            case .connecting:
                self.state = .connecting
            case .connected:
                connectedPeerName = peerID.displayName
                self.state = .connected
                lastError = nil
            @unknown default:
                self.state = .failed
                lastError = "The iPad reported an unsupported connection state."
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}

    enum NearbyError: LocalizedError {
        case noConnectedIPad
        var errorDescription: String? { "Connect to the Kalpana Drive iPad before sharing a destination." }
    }
}
