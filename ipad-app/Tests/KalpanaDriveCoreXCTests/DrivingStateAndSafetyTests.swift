import XCTest
@testable import KalpanaDriveCore

final class DrivingStateAndSafetyTests: XCTestCase {
    func testMovementRequiresSustainedSpeedAndParkingRequiresLongerLowSpeed() {
        var machine = DrivingStateMachine(movingConfirmationDuration: 3, parkedConfirmationDuration: 10)
        let start = Date(timeIntervalSince1970: 1_000)
        let connected = { (speed: Double) in
            DrivingContext(speedMetresPerSecond: speed, phoneConnected: true)
        }

        XCTAssertEqual(machine.update(connected(8), at: start), .parked)
        XCTAssertEqual(machine.update(connected(8), at: start.addingTimeInterval(2.9)), .parked)
        XCTAssertEqual(machine.update(connected(8), at: start.addingTimeInterval(3)), .moving)
        XCTAssertEqual(machine.update(connected(0), at: start.addingTimeInterval(4)), .moving)
        XCTAssertEqual(machine.update(connected(0), at: start.addingTimeInterval(14)), .parked)
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
            phoneConnected: false,
            locationAvailable: false
        ))
        XCTAssertEqual(state, .emergency)
    }

    func testMovingStateBlocksSettingsAndTypingButAllowsVoiceAndEmergency() {
        let policy = DrivingSafetyPolicy()
        XCTAssertFalse(policy.evaluate(.openSettings, state: .moving, source: .touch).isAllowed)
        XCTAssertFalse(policy.evaluate(.typeDestination, state: .moving, source: .touch).isAllowed)
        XCTAssertTrue(policy.evaluate(.typeDestination, state: .moving, source: .voice).isAllowed)
        XCTAssertTrue(policy.evaluate(.controlMedia, state: .moving, source: .touch).isAllowed)
        XCTAssertTrue(policy.evaluate(.emergency, state: .moving, source: .touch).isAllowed)
    }
}
