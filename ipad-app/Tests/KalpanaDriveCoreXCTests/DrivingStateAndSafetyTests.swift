import XCTest
@testable import KalpanaDriveCore

final class DrivingStateAndSafetyTests: XCTestCase {
    func testMovementRequiresSustainedSpeedAndParkingRequiresLongerLowSpeed() {
        var machine = DrivingStateMachine(movingConfirmationDuration: 3, parkedConfirmationDuration: 10)
        let start = Date(timeIntervalSince1970: 1_000)
        let context = { (speed: Double) in DrivingContext(speedMetresPerSecond: speed) }

        XCTAssertEqual(machine.update(context(8), at: start), .parked)
        XCTAssertEqual(machine.update(context(8), at: start.addingTimeInterval(2.9)), .parked)
        XCTAssertEqual(machine.update(context(8), at: start.addingTimeInterval(3)), .moving)
        XCTAssertEqual(machine.update(context(0), at: start.addingTimeInterval(4)), .moving)
        XCTAssertEqual(machine.update(context(0), at: start.addingTimeInterval(14)), .parked)
    }

    func testSafetyPrecedenceIsDeterministic() {
        let machine = DrivingStateMachine()
        let state = machine.resolve(.init(
            speedMetresPerSecond: 20,
            passengerOverride: true,
            emergencyActive: true,
            lowPower: true,
            thermalLimited: true,
            online: false,
            locationAvailable: false
        ))
        XCTAssertEqual(state, .emergency)
    }

    func testMovingStateBlocksComplexInteractionButAllowsVoiceMediaAndEmergency() {
        let policy = DrivingSafetyPolicy()
        XCTAssertTrue(policy.evaluate(.openSettings, state: .moving, source: .touch).isAllowed)
        XCTAssertTrue(policy.evaluate(.typeDestination, state: .moving, source: .touch).isAllowed)
        XCTAssertTrue(policy.evaluate(.typeDestination, state: .moving, source: .voice).isAllowed)
        XCTAssertTrue(policy.evaluate(.controlMedia, state: .moving, source: .touch).isAllowed)
        XCTAssertTrue(policy.evaluate(.emergency, state: .moving, source: .touch).isAllowed)
        XCTAssertTrue(policy.evaluate(.openSettings, state: .locationUnavailable, source: .touch).isAllowed)
    }

    func testPhoneAndExternalMediaSafetyRules() {
        let policy = DrivingSafetyPolicy()
        XCTAssertTrue(policy.evaluate(.browseContacts, state: .moving, source: .touch).isAllowed)
        XCTAssertTrue(policy.evaluate(.browseContacts, state: .moving, source: .voice).isAllowed)
        XCTAssertTrue(policy.evaluate(.typePhoneNumber, state: .moving, source: .touch).isAllowed)
        XCTAssertTrue(policy.evaluate(.typePhoneNumber, state: .parked, source: .touch).isAllowed)
        XCTAssertTrue(policy.evaluate(.placeCall, state: .moving, source: .touch).isAllowed)
        XCTAssertTrue(policy.evaluate(.openExternalMedia, state: .moving, source: .touch).isAllowed)
        XCTAssertTrue(policy.evaluate(.openExternalMedia, state: .parked, source: .touch).isAllowed)
        XCTAssertTrue(policy.evaluate(.manageDevices, state: .moving, source: .touch).isAllowed)
    }

    func testRouteRepositoryRoundTripAndClear() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("active-route.json")
        let repository = JSONRouteRepository(fileURL: url)
        let destination = Destination(
            name: "Selected destination",
            address: "User-selected address",
            coordinate: Coordinate(latitude: 19.076, longitude: 72.8777),
            kind: .recent
        )
        let route = RouteSnapshot(
            destination: destination,
            nextInstruction: "Stored destination only",
            distanceRemainingMetres: 1_500,
            expectedArrival: Date(timeIntervalSince1970: 2_000),
            isActive: true
        )

        try await repository.save(route)
        let restored = try await repository.loadActiveRoute()
        XCTAssertEqual(restored, route)
        try await repository.clear()
        let cleared = try await repository.loadActiveRoute()
        XCTAssertNil(cleared)
    }
}
