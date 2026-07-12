import Foundation

public enum DrivingState: String, Codable, CaseIterable, Sendable {
    case parked = "PARKED"
    case moving = "MOVING"
    case passengerMode = "PASSENGER_MODE"
    case emergency = "EMERGENCY"
    case lowPower = "LOW_POWER"
    case thermalLimit = "THERMAL_LIMIT"
    case offline = "OFFLINE"
    case locationUnavailable = "LOCATION_UNAVAILABLE"

    public var restrictsInteraction: Bool {
        self == .moving || self == .emergency || self == .thermalLimit || self == .lowPower || self == .locationUnavailable
    }
}

public struct DrivingContext: Equatable, Sendable {
    public var speedMetresPerSecond: Double
    public var passengerOverride: Bool
    public var emergencyActive: Bool
    public var lowPower: Bool
    public var thermalLimited: Bool
    public var online: Bool
    public var locationAvailable: Bool

    public init(
        speedMetresPerSecond: Double = 0,
        passengerOverride: Bool = false,
        emergencyActive: Bool = false,
        lowPower: Bool = false,
        thermalLimited: Bool = false,
        online: Bool = true,
        locationAvailable: Bool = true
    ) {
        self.speedMetresPerSecond = speedMetresPerSecond
        self.passengerOverride = passengerOverride
        self.emergencyActive = emergencyActive
        self.lowPower = lowPower
        self.thermalLimited = thermalLimited
        self.online = online
        self.locationAvailable = locationAvailable
    }
}

public struct DrivingStateMachine: Sendable {
    public static let movingThresholdMetresPerSecond = 1.4
    public static let parkedThresholdMetresPerSecond = 0.56

    public var movingConfirmationDuration: TimeInterval
    public var parkedConfirmationDuration: TimeInterval

    private var confirmedMotionState: DrivingState = .parked
    private var candidateSince: Date?

    public init(
        movingConfirmationDuration: TimeInterval = 3,
        parkedConfirmationDuration: TimeInterval = 10
    ) {
        self.movingConfirmationDuration = movingConfirmationDuration
        self.parkedConfirmationDuration = parkedConfirmationDuration
    }

    public func resolve(_ context: DrivingContext) -> DrivingState {
        if context.emergencyActive { return .emergency }
        if context.thermalLimited { return .thermalLimit }
        if context.lowPower { return .lowPower }
        if context.passengerOverride { return .passengerMode }
        if !context.locationAvailable { return .locationUnavailable }
        if context.speedMetresPerSecond >= Self.movingThresholdMetresPerSecond { return .moving }
        if !context.online { return .offline }
        return .parked
    }

    public mutating func update(_ context: DrivingContext, at timestamp: Date = Date()) -> DrivingState {
        if context.emergencyActive { return .emergency }
        if context.thermalLimited { return .thermalLimit }
        if context.lowPower { return .lowPower }
        if context.passengerOverride { return .passengerMode }
        guard context.locationAvailable else {
            candidateSince = nil
            confirmedMotionState = .parked
            return .locationUnavailable
        }

        updateMotionConfirmation(speed: max(0, context.speedMetresPerSecond), at: timestamp)
        if confirmedMotionState == .moving { return .moving }
        if !context.online { return .offline }
        return .parked
    }

    private mutating func updateMotionConfirmation(speed: Double, at timestamp: Date) {
        switch confirmedMotionState {
        case .moving:
            guard speed <= Self.parkedThresholdMetresPerSecond else {
                candidateSince = nil
                return
            }
            if let candidateSince {
                if timestamp.timeIntervalSince(candidateSince) >= parkedConfirmationDuration {
                    confirmedMotionState = .parked
                    self.candidateSince = nil
                }
            } else {
                candidateSince = timestamp
            }
        default:
            guard speed >= Self.movingThresholdMetresPerSecond else {
                candidateSince = nil
                return
            }
            if let candidateSince {
                if timestamp.timeIntervalSince(candidateSince) >= movingConfirmationDuration {
                    confirmedMotionState = .moving
                    self.candidateSince = nil
                }
            } else {
                candidateSince = timestamp
            }
        }
    }
}
