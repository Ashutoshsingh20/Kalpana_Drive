import Foundation

public protocol NavigationProvider: Sendable {
    func calculateRoute(to destination: Destination) async throws -> RouteSnapshot
    func restoreRoute() async -> RouteSnapshot?
    func cancelRoute() async
}

public protocol RouteRepository: Sendable {
    func save(_ route: RouteSnapshot) async throws
    func loadActiveRoute() async throws -> RouteSnapshot?
    func clear() async throws
}

public protocol LocationProvider: Sendable {
    func currentCoordinate() async throws -> Coordinate
    func currentSpeedMetresPerSecond() async -> Double
}

public protocol DestinationSearchProvider: Sendable {
    func search(_ query: String) async throws -> [Destination]
}

public enum MediaCommand: String, Codable, Sendable { case play, pause, previous, next }

public protocol MediaSource: Sendable {
    var displayName: String { get }
    func currentState() async -> MediaSnapshot
}

public protocol MediaController: Sendable {
    func execute(_ command: MediaCommand) async throws
}

public enum AudioRoute: String, Codable, Sendable { case bluetooth, ipadSpeaker, unknown }

public protocol AudioRouteManager: Sendable {
    func currentRoute() async -> AudioRoute
}

public protocol PhoneConnection: Sendable {
    func currentState() async -> PhoneConnectionSnapshot
    func reconnect() async throws
    func disconnect() async
}

public protocol SpeechCommandRouter: Sendable {
    func route(_ transcript: String, state: DrivingState) async -> VoiceResponse
}

public struct VoiceResponse: Equatable, Sendable {
    public var spokenText: String
    public var visualText: String
    public var requiresConfirmation: Bool

    public init(spokenText: String, visualText: String, requiresConfirmation: Bool = false) {
        self.spokenText = spokenText
        self.visualText = visualText
        self.requiresConfirmation = requiresConfirmation
    }
}

