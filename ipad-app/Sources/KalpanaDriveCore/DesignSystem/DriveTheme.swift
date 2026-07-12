import Foundation

public enum DriveAppearance: String, Codable, CaseIterable, Sendable {
    case day, night, highSunlight
}

public enum ControlHand: String, Codable, CaseIterable, Sendable {
    case left, right
}

public enum DriveMetrics {
    public static let minimumTouchTarget: Double = 60
    public static let cardCornerRadius: Double = 12
    public static let dashboardSpacing: Double = 16
}
