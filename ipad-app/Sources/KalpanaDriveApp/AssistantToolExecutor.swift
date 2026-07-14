import Foundation
import KalpanaDriveCore

@MainActor
final class AssistantToolExecutor {
    private let viewModel: DashboardViewModel

    init(viewModel: DashboardViewModel) {
        self.viewModel = viewModel
    }

    func execute(
        toolCall: AssistantToolCall,
        onRequireConfirmation: @escaping (String, @escaping () -> Void) -> Void
    ) -> AssistantToolResult {
        let toolName = toolCall.name
        let params = toolCall.parameters

        switch toolName {
        case .navigate:
            guard let dest = params.destination, !dest.isEmpty else {
                return AssistantToolResult(
                    status: .failed,
                    userFacingMessage: "Destination name is missing.",
                    technicalReason: "destination parameter is null or empty",
                    resultingEntityId: nil
                )
            }
            
            // Check if confirmation is required
            let action = { [weak self] in
                guard let self = self else { return }
                self.viewModel.destinationQuery = dest
                self.viewModel.searchDestinations()
                self.viewModel.selectSection(.map)
            }
            
            onRequireConfirmation("Start route search to \(dest)?", action)
            return AssistantToolResult(
                status: .awaitingConfirmation,
                userFacingMessage: "Calculate route to \(dest)?",
                technicalReason: nil,
                resultingEntityId: nil
            )

        case .search:
            guard let category = params.category, !category.isEmpty else {
                return AssistantToolResult(
                    status: .failed,
                    userFacingMessage: "Search category is missing.",
                    technicalReason: "category parameter is null or empty",
                    resultingEntityId: nil
                )
            }
            viewModel.destinationQuery = category
            viewModel.searchDestinations()
            viewModel.selectSection(.map)
            return AssistantToolResult(
                status: .started,
                userFacingMessage: "Searching for \(category) nearby.",
                technicalReason: nil,
                resultingEntityId: nil
            )

        case .call:
            guard let name = params.name, !name.isEmpty else {
                return AssistantToolResult(
                    status: .failed,
                    userFacingMessage: "Contact name is missing.",
                    technicalReason: "name parameter is null or empty",
                    resultingEntityId: nil
                )
            }
            
            let matches = viewModel.nativeContacts.filter { $0.displayName.localizedCaseInsensitiveContains(name) }
            
            // Store matched contacts in AI coordinator's context for follow-up selection!
            viewModel.aiCoordinator.conversationalContext.lastMatchedContacts = matches
            
            if matches.isEmpty {
                if let number = params.number, !number.isEmpty {
                    let action = { [weak self] in
                        guard let self = self else { return }
                        self.viewModel.call(number: number)
                    }
                    onRequireConfirmation("Call \(name) at \(number)?", action)
                    return AssistantToolResult(
                        status: .awaitingConfirmation,
                        userFacingMessage: "Open phone dialer to call \(name) at \(number)?",
                        technicalReason: nil,
                        resultingEntityId: nil
                    )
                }
                return AssistantToolResult(
                    status: .failed,
                    userFacingMessage: "No contacts matched '\(name)' in your directory.",
                    technicalReason: "contacts search returned empty list",
                    resultingEntityId: nil
                )
            } else if matches.count > 1 {
                let matchesList = matches.map { $0.displayName }.joined(separator: ", ")
                return AssistantToolResult(
                    status: .failed,
                    userFacingMessage: "Multiple contacts matched '\(name)': \(matchesList). Please be more specific.",
                    technicalReason: "multiple contacts matched",
                    resultingEntityId: nil
                )
            } else {
                let match = matches.first!
                
                // Check if contact has multiple phone numbers
                if match.phoneNumbers.count > 1 {
                    let numbersList = match.phoneNumbers.map { "\($0.label): \($0.number)" }.joined(separator: ", ")
                    return AssistantToolResult(
                        status: .failed,
                        userFacingMessage: "\(match.displayName) has multiple numbers: \(numbersList). Please specify which label (e.g. mobile or work) to call.",
                        technicalReason: "multiple numbers for contact",
                        resultingEntityId: match.id
                    )
                }
                
                guard let phone = match.phoneNumbers.first?.number else {
                    return AssistantToolResult(
                        status: .failed,
                        userFacingMessage: "\(match.displayName) has no phone numbers saved.",
                        technicalReason: "no phone numbers found",
                        resultingEntityId: match.id
                    )
                }
                
                let action = { [weak self] in
                    guard let self = self else { return }
                    self.viewModel.call(number: phone, contactId: match.id)
                }
                onRequireConfirmation("Opening phone dialer to call \(match.displayName) (\(phone))?", action)
                return AssistantToolResult(
                    status: .awaitingConfirmation,
                    userFacingMessage: "Opening phone dialer to call \(match.displayName) (\(phone))?",
                    technicalReason: nil,
                    resultingEntityId: match.id
                )
            }

        case .savePlace:
            guard let placeName = params.name, !placeName.isEmpty,
                  let labelStr = params.label,
                  let coord = viewModel.currentCoordinate else {
                return AssistantToolResult(
                    status: .failed,
                    userFacingMessage: "Place name or label is missing.",
                    technicalReason: "missing required parameters or GPS coordinates",
                    resultingEntityId: nil
                )
            }
            let label: SavedPlaceLabel = switch labelStr.lowercased() {
            case "home": .home
            case "work": .work
            case "college": .college
            default: .custom
            }
            let action = { [weak self] in
                guard let self = self else { return }
                self.viewModel.savePlace(name: placeName, address: "Current Location", coordinate: coord, label: label)
            }
            onRequireConfirmation("Save your current location as \(placeName) (\(labelStr))?", action)
            return AssistantToolResult(
                status: .awaitingConfirmation,
                userFacingMessage: "Save current location as \(placeName)?",
                technicalReason: nil,
                resultingEntityId: nil
            )

        case .showParking:
            viewModel.navigateToParking()
            viewModel.selectSection(.map)
            return AssistantToolResult(
                status: .completed,
                userFacingMessage: "Showing recorded parking location.",
                technicalReason: nil,
                resultingEntityId: nil
            )

        case .showTrips:
            // Open the actual trips history sheet
            viewModel.showTripHistory = true
            viewModel.selectSection(.map)
            return AssistantToolResult(
                status: .completed,
                userFacingMessage: "Showing recorded trip logs.",
                technicalReason: nil,
                resultingEntityId: nil
            )

        case .avoidRoad:
            guard let road = params.roadName, !road.isEmpty else {
                return AssistantToolResult(
                    status: .failed,
                    userFacingMessage: "Road name is missing.",
                    technicalReason: "roadName is empty",
                    resultingEntityId: nil
                )
            }
            let action = { [weak self] in
                guard let self = self else { return }
                self.viewModel.avoidRoad(road)
            }
            onRequireConfirmation("Avoid \(road) in trip planning?", action)
            return AssistantToolResult(
                status: .awaitingConfirmation,
                userFacingMessage: "Avoid \(road) in trip planning?",
                technicalReason: nil,
                resultingEntityId: nil
            )

        case .preferRoad:
            guard let road = params.roadName, !road.isEmpty else {
                return AssistantToolResult(
                    status: .failed,
                    userFacingMessage: "Road name is missing.",
                    technicalReason: "roadName is empty",
                    resultingEntityId: nil
                )
            }
            let action = { [weak self] in
                guard let self = self else { return }
                self.viewModel.preferRoad(road)
            }
            onRequireConfirmation("Prefer \(road) in trip planning?", action)
            return AssistantToolResult(
                status: .awaitingConfirmation,
                userFacingMessage: "Prefer \(road) in trip planning?",
                technicalReason: nil,
                resultingEntityId: nil
            )

        case .none:
            return AssistantToolResult(
                status: .completed,
                userFacingMessage: "I parsed your request, but no action is needed.",
                technicalReason: nil,
                resultingEntityId: nil
            )
        }
    }
}
