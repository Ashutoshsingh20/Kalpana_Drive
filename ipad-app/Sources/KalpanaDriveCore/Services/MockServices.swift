import Foundation

public actor MockLocationProvider: LocationProvider {
    private var speed: Double
    public init(speedMetresPerSecond: Double = 0) { speed = speedMetresPerSecond }
    public func setSpeed(_ value: Double) { speed = max(0, value) }
    public func currentCoordinate() async throws -> Coordinate { Coordinate(latitude: 28.6139, longitude: 77.2090) }
    public func currentSpeedMetresPerSecond() async -> Double { speed }
}

public actor MockNavigationProvider: NavigationProvider {
    private var route: RouteSnapshot?
    public init(route: RouteSnapshot? = nil) { self.route = route }
    public func calculateRoute(to destination: Destination) async throws -> RouteSnapshot {
        let result = RouteSnapshot(destination: destination, nextInstruction: "Continue straight", distanceRemainingMetres: 8_400, expectedArrival: Date().addingTimeInterval(1_200), isActive: true)
        route = result
        return result
    }
    public func restoreRoute() async -> RouteSnapshot? { route }
    public func cancelRoute() async { route = nil }
}

public actor MockMediaService: MediaSource, MediaController {
    public nonisolated let displayName = "Simulated media"
    private var snapshot = MediaSnapshot(title: "Driving Mix", artist: "Kalpana Drive", isPlaying: false, elapsed: 42, duration: 214)
    public init() {}
    public func currentState() async -> MediaSnapshot { snapshot }
    public func execute(_ command: MediaCommand) async throws {
        if command == .play { snapshot.isPlaying = true }
        if command == .pause { snapshot.isPlaying = false }
    }
}

public actor MockPhoneConnection: PhoneConnection {
    private var snapshot = PhoneConnectionSnapshot(state: .disconnected, platform: .none, deviceName: nil, lastHeartbeat: nil)
    public init() {}
    public func currentState() async -> PhoneConnectionSnapshot { snapshot }
    public func reconnect() async throws { snapshot.state = .connecting }
    public func disconnect() async { snapshot.state = .disconnected }
}

public struct MockAudioRouteManager: AudioRouteManager {
    public init() {}
    public func currentRoute() async -> AudioRoute { .unknown }
}

