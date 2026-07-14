import Foundation
import KalpanaDriveCore

@main
struct KalpanaDriveChecks {
    static func main() async throws {
        try checkDrivingStateMachine()
        try checkSafetyPolicy()
        try await checkRecoveryStore()
        try await checkRouteRepository()
        print("KalpanaDriveChecks: 23 checks passed")
    }

    private static func checkSafetyPolicy() throws {
        let policy = DrivingSafetyPolicy()
        try expect(policy.evaluate(.controlMedia, state: .moving, source: .touch).isAllowed, "large media controls remain available")
        try expect(policy.evaluate(.emergency, state: .moving, source: .touch).isAllowed, "emergency remains available")
        try expect(policy.evaluate(.openSettings, state: .moving, source: .touch).isAllowed, "settings are allowed while moving")
        try expect(policy.evaluate(.openSettings, state: .parked, source: .touch).isAllowed, "settings are allowed while parked")
        try expect(policy.evaluate(.typeDestination, state: .moving, source: .touch).isAllowed, "destination typing is allowed while moving")
        try expect(policy.evaluate(.typeDestination, state: .moving, source: .voice).isAllowed, "voice destination entry is allowed while moving")
        try expect(policy.evaluate(.manageDevices, state: .thermalLimit, source: .touch).isAllowed, "device management is allowed under thermal limit")
        try expect(policy.classification(for: .browseContent) == .voiceOnlyWhileMoving, "content browsing has one central classification")
    }

    private static func checkDrivingStateMachine() throws {
        var machine = DrivingStateMachine(movingConfirmationDuration: 3, parkedConfirmationDuration: 10)
        let moving = machine.resolve(.init(speedMetresPerSecond: 1.4))
        try expect(moving == .moving, "speed threshold enters MOVING")
        try expect(!moving.restrictsInteraction, "MOVING does not restrict interaction")

        let emergency = machine.resolve(.init(
            speedMetresPerSecond: 20,
            passengerOverride: true,
            emergencyActive: true,
            lowPower: true,
            thermalLimited: true,
            online: true,
            locationAvailable: true
        ))
        try expect(emergency == .emergency, "emergency has highest precedence")
        try expect(machine.resolve(.init(speedMetresPerSecond: 20, passengerOverride: true)) == .passengerMode, "passenger mode is explicit")
        try expect(machine.resolve(.init(online: false)) == .offline, "offline mode handled")
        try expect(!machine.resolve(.init()).restrictsInteraction, "parked does not lock parked controls")
        try expect(machine.resolve(.init(locationAvailable: false)) == .locationUnavailable, "missing GPS is explicit")

        let start = Date(timeIntervalSince1970: 1_000)
        try expect(machine.update(.init(speedMetresPerSecond: 8), at: start) == .parked, "one fast sample does not enter moving")
        try expect(machine.update(.init(speedMetresPerSecond: 8), at: start.addingTimeInterval(2.9)) == .parked, "movement requires sustained speed")
        try expect(machine.update(.init(speedMetresPerSecond: 8), at: start.addingTimeInterval(3)) == .moving, "sustained speed enters moving")
        try expect(machine.update(.init(speedMetresPerSecond: 0), at: start.addingTimeInterval(4)) == .moving, "one slow sample does not park")
        try expect(machine.update(.init(speedMetresPerSecond: 0), at: start.addingTimeInterval(14)) == .parked, "sustained low speed parks")
    }

    private static func checkRecoveryStore() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("recovery.json")
        let store = RecoveryStore(fileURL: url)
        let snapshot = DashboardSnapshot(
            route: nil,
            media: .init(title: "Test", artist: "Artist", isPlaying: true, elapsed: 1, duration: 2),
            phone: .init(state: .unavailable, platform: .none, deviceName: nil, lastHeartbeat: nil),
            savedAt: Date(timeIntervalSince1970: 100)
        )
        try await store.save(snapshot)
        let restored = try await store.load()
        try expect(restored == snapshot, "recovery snapshot round trip")
        try await store.clear()
    }

    private static func checkRouteRepository() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("active-route.json")
        let repository = JSONRouteRepository(fileURL: url)
        let destination = Destination(
            name: "Configured place",
            address: "Real user-selected address",
            coordinate: Coordinate(latitude: 19.076, longitude: 72.8777),
            kind: .recent
        )
        let route = RouteSnapshot(
            destination: destination,
            nextInstruction: "Recalculate after launch",
            distanceRemainingMetres: 1_500,
            expectedArrival: Date(timeIntervalSince1970: 2_000),
            isActive: true
        )
        try await repository.save(route)
        let restored = try await repository.loadActiveRoute()
        try expect(restored == route, "active route persists")
        try await repository.clear()
        let cleared = try await repository.loadActiveRoute()
        try expect(cleared == nil, "cancelled route is removed")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw CheckFailure(message: message) }
    }

    private struct CheckFailure: Error, CustomStringConvertible {
        let message: String
        var description: String { "Check failed: \(message)" }
    }
}
