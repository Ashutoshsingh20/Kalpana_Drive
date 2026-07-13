import AppIntents
import Foundation

struct SiriDriveCommand: Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case openDashboard
        case openMap
        case openMusic
        case searchDestination
    }

    let kind: Kind
    let value: String?
    let createdAt: Date
}

enum SiriDriveCommandStore {
    private static let commandKey = "kalpana.drive.pending-siri-command"

    static func enqueue(_ kind: SiriDriveCommand.Kind, value: String? = nil) {
        let command = SiriDriveCommand(kind: kind, value: value, createdAt: Date())
        guard let data = try? JSONEncoder().encode(command) else { return }
        UserDefaults.standard.set(data, forKey: commandKey)
    }

    static func consume() -> SiriDriveCommand? {
        guard let data = UserDefaults.standard.data(forKey: commandKey),
              let command = try? JSONDecoder().decode(SiriDriveCommand.self, from: data) else {
            return nil
        }
        UserDefaults.standard.removeObject(forKey: commandKey)
        guard abs(command.createdAt.timeIntervalSinceNow) < 120 else { return nil }
        return command
    }
}

struct OpenDriveDashboardIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Drive Dashboard"
    static let description = IntentDescription("Opens the main Kalpana Drive dashboard.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        SiriDriveCommandStore.enqueue(.openDashboard)
        return .result(dialog: "Opening the driving dashboard.")
    }
}

struct OpenDriveMapIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Drive Map"
    static let description = IntentDescription("Opens the map inside Kalpana Drive.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        SiriDriveCommandStore.enqueue(.openMap)
        return .result(dialog: "Opening the map in Kalpana Drive.")
    }
}

struct OpenDriveMusicIntent: AppIntent {
    static let title: LocalizedStringResource = "Open YouTube Music"
    static let description = IntentDescription("Opens the YouTube Music screen inside Kalpana Drive.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        SiriDriveCommandStore.enqueue(.openMusic)
        return .result(dialog: "Opening YouTube Music in Kalpana Drive.")
    }
}

struct SearchDriveDestinationIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Drive Destination"
    static let description = IntentDescription("Searches for a destination inside Kalpana Drive.")
    static let openAppWhenRun = true

    @Parameter(title: "Destination")
    var destination: String

    static var parameterSummary: some ParameterSummary {
        Summary("Search for \(.$destination)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let cleaned = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return .result(dialog: "Tell me which destination to search for.")
        }
        SiriDriveCommandStore.enqueue(.searchDestination, value: cleaned)
        return .result(dialog: "Searching for \(cleaned) in Kalpana Drive.")
    }
}

struct KalpanaDriveAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenDriveDashboardIntent(),
            phrases: [
                "Open the dashboard in \(.applicationName)",
                "Show \(.applicationName) dashboard"
            ],
            shortTitle: "Drive Dashboard",
            systemImageName: "car.fill"
        )

        AppShortcut(
            intent: OpenDriveMapIntent(),
            phrases: [
                "Open the map in \(.applicationName)",
                "Show the map in \(.applicationName)"
            ],
            shortTitle: "Drive Map",
            systemImageName: "map.fill"
        )

        AppShortcut(
            intent: OpenDriveMusicIntent(),
            phrases: [
                "Open YouTube Music in \(.applicationName)",
                "Play music with \(.applicationName)"
            ],
            shortTitle: "YouTube Music",
            systemImageName: "play.rectangle.fill"
        )

        AppShortcut(
            intent: SearchDriveDestinationIntent(),
            phrases: [
                "Search for \(.$destination) in \(.applicationName)",
                "Find \(.$destination) with \(.applicationName)"
            ],
            shortTitle: "Search Destination",
            systemImageName: "location.magnifyingglass"
        )
    }
}
