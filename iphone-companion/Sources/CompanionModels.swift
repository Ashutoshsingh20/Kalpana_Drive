import Foundation

struct CompanionEnvelope: Codable, Sendable {
    let version: Int
    let id: UUID
    let type: MessageType
    let deviceID: UUID
    let timestamp: Date
    let sequence: UInt64
    let payload: Data

    init<T: Encodable>(
        type: MessageType,
        deviceID: UUID,
        sequence: UInt64,
        payload: T
    ) throws {
        self.version = 1
        self.id = UUID()
        self.type = type
        self.deviceID = deviceID
        self.timestamp = Date()
        self.sequence = sequence
        self.payload = try JSONEncoder.companion.encode(payload)
    }

    func decodePayload<T: Decodable>(_ type: T.Type) throws -> T {
        try JSONDecoder.companion.decode(type, from: payload)
    }
}

enum MessageType: String, Codable, Sendable {
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

struct DeviceHello: Codable, Sendable {
    let name: String
    let platform: String
    let appVersion: String
    let capabilities: [String]
}

struct PhoneDeviceState: Codable, Sendable {
    let batteryPercent: Int?
    let isCharging: Bool
    let isOnline: Bool
    let updatedAt: Date
}

struct ContactRecord: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let phoneNumbers: [String]
}

struct PhoneMediaState: Codable, Equatable, Sendable {
    let title: String?
    let artist: String?
    let album: String?
    let isPlaying: Bool
    let elapsed: TimeInterval
    let duration: TimeInterval
    let updatedAt: Date

    static let unavailable = PhoneMediaState(
        title: nil,
        artist: nil,
        album: nil,
        isPlaying: false,
        elapsed: 0,
        duration: 0,
        updatedAt: Date()
    )
}

enum PhoneMediaCommand: String, Codable, Sendable {
    case play
    case pause
    case previous
    case next
}

struct MediaCommandRequest: Codable, Sendable {
    let command: PhoneMediaCommand
}

struct MediaCommandResult: Codable, Sendable {
    let command: PhoneMediaCommand
    let succeeded: Bool
    let message: String
}

struct SharedLocationState: Codable, Sendable {
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double
    let timestamp: Date
}

struct CalendarDestination: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let location: String
    let startDate: Date
}

struct CompanionErrorPayload: Codable, Sendable {
    let code: String
    let message: String
}

extension JSONEncoder {
    static var companion: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var companion: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}
