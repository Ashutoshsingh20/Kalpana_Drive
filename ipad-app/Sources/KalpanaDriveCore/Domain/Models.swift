import Foundation

public struct Coordinate: Codable, Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public struct Destination: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var address: String
    public var coordinate: Coordinate
    public var kind: Kind

    public enum Kind: String, Codable, Sendable { case home, college, work, favourite, recent }

    public init(id: UUID = UUID(), name: String, address: String, coordinate: Coordinate, kind: Kind) {
        self.id = id
        self.name = name
        self.address = address
        self.coordinate = coordinate
        self.kind = kind
    }
}

public struct RouteSnapshot: Codable, Equatable, Sendable {
    public var destination: Destination
    public var nextInstruction: String
    public var distanceRemainingMetres: Double
    public var expectedArrival: Date
    public var isActive: Bool
}

public struct MediaSnapshot: Codable, Equatable, Sendable {
    public var title: String
    public var artist: String
    public var isPlaying: Bool
    public var elapsed: TimeInterval
    public var duration: TimeInterval

    public init(title: String, artist: String, isPlaying: Bool, elapsed: TimeInterval, duration: TimeInterval) {
        self.title = title
        self.artist = artist
        self.isPlaying = isPlaying
        self.elapsed = elapsed
        self.duration = duration
    }
}

public enum ConnectionState: String, Codable, Sendable { case disconnected, pairing, connecting, connected, stale }
public enum PhonePlatform: String, Codable, Sendable { case iPhone, android, none }

public struct PhoneConnectionSnapshot: Codable, Equatable, Sendable {
    public var state: ConnectionState
    public var platform: PhonePlatform
    public var deviceName: String?
    public var lastHeartbeat: Date?

    public init(state: ConnectionState, platform: PhonePlatform, deviceName: String?, lastHeartbeat: Date?) {
        self.state = state
        self.platform = platform
        self.deviceName = deviceName
        self.lastHeartbeat = lastHeartbeat
    }
}

public struct DashboardSnapshot: Codable, Equatable, Sendable {
    public var route: RouteSnapshot?
    public var media: MediaSnapshot
    public var phone: PhoneConnectionSnapshot
    public var savedAt: Date

    public init(route: RouteSnapshot?, media: MediaSnapshot, phone: PhoneConnectionSnapshot, savedAt: Date) {
        self.route = route
        self.media = media
        self.phone = phone
        self.savedAt = savedAt
    }
}
