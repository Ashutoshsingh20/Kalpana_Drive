import Foundation
import KalpanaDriveCore

@MainActor
final class AssistantToolExecutor {
    private let viewModel: DashboardViewModel

    init(viewModel: DashboardViewModel) {
        self.viewModel = viewModel
    }

    func execute(toolCall: AssistantToolCall, onRequireConfirmation: @escaping (String, @escaping () -> Void) -> Void) -> String {
        guard let toolType = ToolType(rawValue: toolCall.name) else {
            return "Tool \(toolCall.name) is unknown or not supported."
        }

        let params = toolCall.parameters

        switch toolType {
        case .navigate:
            guard let dest = params.destination, !dest.isEmpty else {
                return "Destination name is missing."
            }
            let action = {
                self.viewModel.destinationQuery = dest
                self.viewModel.searchDestinations()
                self.viewModel.selectSection(.map)
            }
            onRequireConfirmation("Start navigation to \(dest)?", action)
            return "Preparing route to \(dest)."

        case .search:
            guard let category = params.category, !category.isEmpty else {
                return "Search category is missing."
            }
            viewModel.destinationQuery = category
            viewModel.searchDestinations()
            viewModel.selectSection(.map)
            return "Searching for \(category) near you."

        case .call:
            guard let name = params.name, !name.isEmpty else {
                return "Contact name is missing."
            }
            
            // Search contact locally
            let matches = viewModel.nativeContacts.filter { $0.displayName.localizedCaseInsensitiveContains(name) }
            if matches.isEmpty {
                if let number = params.number, !number.isEmpty {
                    let action = { self.viewModel.call(number: number) }
                    onRequireConfirmation("Call \(name) at \(number)?", action)
                    return "Dialing \(number)."
                }
                return "No contacts matched \(name) in your directory."
            } else if matches.count > 1 {
                // Ambiguous contacts require confirmation
                let match = matches.first!
                let number = match.phoneNumbers.first?.number ?? ""
                let action = { self.viewModel.call(number: number, contactId: match.id) }
                onRequireConfirmation("Multiple matches found. Call \(match.displayName) (\(number))?", action)
                return "Found multiple matches. Would you like to call \(match.displayName)?"
            } else {
                let match = matches.first!
                let number = match.phoneNumbers.first?.number ?? ""
                let action = { self.viewModel.call(number: number, contactId: match.id) }
                onRequireConfirmation("Call \(match.displayName) (\(number))?", action)
                return "Preparing call to \(match.displayName)."
            }

        case .savePlace:
            guard let placeName = params.name, !placeName.isEmpty,
                  let labelStr = params.label,
                  let coord = viewModel.currentCoordinate else {
                return "Place name or label is missing."
            }
            let label: SavedPlaceLabel = switch labelStr.lowercased() {
            case "home": .home
            case "work": .work
            case "college": .college
            default: .custom
            }
            let action = {
                self.viewModel.savePlace(name: placeName, address: "Current Location", coordinate: coord, label: label)
            }
            onRequireConfirmation("Save your current location as \(placeName) (\(labelStr))?", action)
            return "Saving current location as \(placeName)."

        case .showParking:
            viewModel.navigateToParking()
            viewModel.selectSection(.map)
            return "Showing your recorded parking location."

        case .showTrips:
            viewModel.selectSection(.map)
            return "Showing recorded trip logs."

        case .avoidRoad:
            guard let road = params.roadName, !road.isEmpty else {
                return "Road name is missing."
            }
            let action = {
                self.viewModel.avoidRoad(road)
            }
            onRequireConfirmation("Avoid \(road) in trip planning?", action)
            return "Adding \(road) to avoided roads."

        case .preferRoad:
            guard let road = params.roadName, !road.isEmpty else {
                return "Road name is missing."
            }
            let action = {
                self.viewModel.preferRoad(road)
            }
            onRequireConfirmation("Prefer \(road) in trip planning?", action)
            return "Adding \(road) to preferred roads."
        }
    }

    enum ToolType: String {
        case navigate = "navigate"
        case search = "search"
        case call = "call"
        case savePlace = "save_place"
        case showParking = "show_parking"
        case showTrips = "show_trips"
        case avoidRoad = "avoid_road"
        case preferRoad = "prefer_road"
    }
}

// Security validations
struct AssistantToolCall: Codable {
    let name: String
    let parameters: AssistantToolParameters
}

struct AssistantToolParameters: Codable {
    let destination: String?
    let category: String?
    let bias: String?
    let name: String?
    let number: String?
    let label: String?
    let roadName: String?
}

struct AssistantModelResponse: Codable {
    let explanation: String
    let toolCall: AssistantToolCall?
    let needsConfirmation: Bool?
}
