import Foundation

public enum DrivingState: String, Codable, CaseIterable, Sendable {
    case parked = "PARKED"
    case moving = "MOVING"
    case passengerMode = "PASSENGER_MODE"
    case emergency = "EMERGENCY"
    case lowPower = "LOW_POWER"
    case thermalLimit = "THERMAL_LIMIT"
    case offline = "OFFLINE"
    case phoneDisconnected = "PHONE_DISCONNECTED"

    public var restrictsInteraction: Bool {
        self == .moving || self == .emergency || self == .thermalLimit
    }
}

public struct DrivingContext: Equatable, Sendable {
    public var speedMetresPerSecond: Double
    public var passengerOverride: Bool
    public var emergencyActive: Bool
    public var lowPower: Bool
    public var thermalLimited: Bool
    public var online: Bool
    public var phoneConnected: Bool

    public init(
        speedMetresPerSecond: Double = 0,
        passengerOverride: Bool = false,
        emergencyActive: Bool = false,
        lowPower: Bool = false,
        thermalLimited: Bool = false,
        online: Bool = true,
        phoneConnected: Bool = false
    ) {
        self.speedMetresPerSecond = speedMetresPerSecond
        self.passengerOverride = passengerOverride
        self.emergencyActive = emergencyActive
        self.lowPower = lowPower
        self.thermalLimited = thermalLimited
        self.online = online
        self.phoneConnected = phoneConnected
    }
}

public struct DrivingStateMachine: Sendable {
    public static let movingThresholdMetresPerSecond = 1.4

    public init() {}

    public func resolve(_ context: DrivingContext) -> DrivingState {
        if context.emergencyActive { return .emergency }
        if context.thermalLimited { return .thermalLimit }
        if context.lowPower { return .lowPower }
        if context.passengerOverride { return .passengerMode }
        if context.speedMetresPerSecond >= Self.movingThresholdMetresPerSecond { return .moving }
        if !context.online { return .offline }
        if !context.phoneConnected { return .phoneDisconnected }
        return .parked
    }
}

