import Foundation
import KalpanaDriveCore

@main
struct KalpanaDriveChecks {
    static func main() async throws {
        try checkDrivingStateMachine()
        try await checkRecoveryStore()
        print("KalpanaDriveChecks: 7 checks passed")
    }

    private static func checkDrivingStateMachine() throws {
        let machine = DrivingStateMachine()
        let moving = machine.resolve(.init(speedMetresPerSecond: 1.4, phoneConnected: true))
        try expect(moving == .moving, "speed threshold enters MOVING")
        try expect(moving.restrictsInteraction, "MOVING restricts interaction")

        let emergency = machine.resolve(.init(
            speedMetresPerSecond: 20,
            passengerOverride: true,
            emergencyActive: true,
            lowPower: true,
            thermalLimited: true,
            online: false,
            phoneConnected: false
        ))
        try expect(emergency == .emergency, "emergency has highest precedence")
        try expect(machine.resolve(.init(speedMetresPerSecond: 20, passengerOverride: true, phoneConnected: true)) == .passengerMode, "passenger mode is explicit")
        try expect(machine.resolve(.init(online: false, phoneConnected: false)) == .offline, "offline precedes disconnected phone")
        try expect(!machine.resolve(.init(phoneConnected: false)).restrictsInteraction, "disconnected phone does not lock parked controls")
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

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw CheckFailure(message: message) }
    }

    private struct CheckFailure: Error, CustomStringConvertible {
        let message: String
        var description: String { "Check failed: \(message)" }
    }
}
