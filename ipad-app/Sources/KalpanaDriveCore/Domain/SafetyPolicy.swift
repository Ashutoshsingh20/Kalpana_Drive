import Foundation

public enum DrivingAction: String, CaseIterable, Sendable {
    case openDashboard
    case openMap
    case openMusic
    case openPhone
    case openSettings
    case controlMedia
    case useVoice
    case typeDestination
    case browseContent
    case manageDevices
    case emergency
}

public enum SafetyClassification: String, Sendable {
    case alwaysAllowed = "ALWAYS_ALLOWED"
    case voiceOnlyWhileMoving = "VOICE_ONLY_WHILE_MOVING"
    case parkedOnly = "PARKED_ONLY"
    case emergency = "EMERGENCY"
    case blocked = "BLOCKED"
}

public enum ActionSource: String, Sendable {
    case touch
    case voice
    case system
}

public struct SafetyDecision: Equatable, Sendable {
    public let isAllowed: Bool
    public let classification: SafetyClassification
    public let reason: String?

    public init(isAllowed: Bool, classification: SafetyClassification, reason: String? = nil) {
        self.isAllowed = isAllowed
        self.classification = classification
        self.reason = reason
    }
}

public struct DrivingSafetyPolicy: Sendable {
    public init() {}

    public func classification(for action: DrivingAction) -> SafetyClassification {
        switch action {
        case .openDashboard, .openMap, .openMusic, .openPhone, .controlMedia, .useVoice:
            .alwaysAllowed
        case .typeDestination, .browseContent:
            .voiceOnlyWhileMoving
        case .openSettings, .manageDevices:
            .parkedOnly
        case .emergency:
            .emergency
        }
    }

    public func evaluate(
        _ action: DrivingAction,
        state: DrivingState,
        source: ActionSource
    ) -> SafetyDecision {
        let classification = classification(for: action)
        switch classification {
        case .alwaysAllowed, .emergency:
            return SafetyDecision(isAllowed: true, classification: classification)
        case .blocked:
            return SafetyDecision(isAllowed: false, classification: classification, reason: "This action is unavailable.")
        case .voiceOnlyWhileMoving:
            guard state == .moving, source != .voice else {
                return SafetyDecision(isAllowed: true, classification: classification)
            }
            return SafetyDecision(
                isAllowed: false,
                classification: classification,
                reason: "Use Kalpana voice control for this action while moving."
            )
        case .parkedOnly:
            let parkedStates: Set<DrivingState> = [.parked, .offline, .phoneDisconnected, .locationUnavailable, .passengerMode]
            guard parkedStates.contains(state) else {
                return SafetyDecision(
                    isAllowed: false,
                    classification: classification,
                    reason: "This control is available only while parked."
                )
            }
            return SafetyDecision(isAllowed: true, classification: classification)
        }
    }
}
