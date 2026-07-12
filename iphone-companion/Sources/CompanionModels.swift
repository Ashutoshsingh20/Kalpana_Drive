import Foundation

struct CompanionEnvelope<Payload: Codable>: Codable {
    let version: Int
    let id: UUID
    let type: String
    let deviceId: UUID
    let timestamp: Int64
    let sequence: UInt64
    let payload: Payload
}

struct SharedDestinationPayload: Codable {
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
}

enum NearbyConnectionState: String {
    case searching = "Searching"
    case inviting = "Inviting"
    case connecting = "Connecting"
    case connected = "Connected"
    case disconnected = "Disconnected"
    case failed = "Failed"
}

