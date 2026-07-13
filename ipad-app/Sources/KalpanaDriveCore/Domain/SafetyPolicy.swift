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
    case browseContacts
    case typePhoneNumber
    case placeCall
    case openExternalMedia
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
        case .openDashboard, .openMap, .openMusic, .openPhone, .controlMedia, .useVoice, .placeCall:
            .alwaysAllowed
        case .typeDestination, .browseContent, .browseContacts:
            .voiceOnlyWhileMoving
        case .openSettings, .typePhoneNumber, .openExternalMedia, .manageDevices:
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
        return SafetyDecision(isAllowed: true, classification: classification, reason: nil)
    }
}
