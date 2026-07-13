import Foundation
import CoreLocation
import KalpanaDriveCore

@MainActor
final class AICoordinator: ObservableObject {
    @Published var conversationHistory: [ChatMessage] = []
    @Published var isProcessing = false
    @Published var pendingAction: PendingAction?

    private var apiKey: String {
        KeychainHelper.shared.loadApiKey() ?? ""
    }
    private let endpoint = "https://integrate.api.nvidia.com/v1/chat/completions"
    private let modelName = "meta/llama-3.1-8b-instruct"

    struct ChatMessage: Identifiable, Codable {
        let id: UUID
        let role: String
        let content: String
        let timestamp: Date

        init(role: String, content: String) {
            self.id = UUID()
            self.role = role
            self.content = content
            self.timestamp = Date()
        }
    }

    struct PendingAction: Identifiable {
        let id: UUID
        let title: String
        let message: String
        let onConfirm: () -> Void

        init(title: String, message: String, onConfirm: @escaping () -> Void) {
            self.id = UUID()
            self.title = title
            self.message = message
            self.onConfirm = onConfirm
        }
    }

    func clearHistory() {
        conversationHistory = []
        pendingAction = nil
    }

    func processUserRequest(_ query: String, viewModel: DashboardViewModel) async {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        conversationHistory.append(ChatMessage(role: "user", content: query))
        isProcessing = true
        defer { isProcessing = false }

        // Local state representation to provide context to the LLM
        let gpsContext = viewModel.locationAccuracy
        let speed = "\(viewModel.speedKPH) km/h"
        let activeDest = viewModel.activeRoute?.destination.name ?? "None"
        let savedPlacesList = viewModel.savedPlaces.map { "\($0.name) (\($0.label.rawValue))" }.joined(separator: ", ")

        let systemPrompt = """
        You are the intelligent on-device coordinator for Kalpana Drive, an iPadOS infotainment system.
        Your goal is to parse the user's natural language queries and map them to one of the available system tools.
        Do not calculate maps, routes, traffic, or contact information yourself. Always call the corresponding system tools.

        State Context:
        - GPS accuracy: \(gpsContext)
        - Current speed: \(speed)
        - Active navigation destination: \(activeDest)
        - Saved places: [\(savedPlacesList)]

        Available Tools:
        1. "navigate" - starts navigation to a destination or query.
           Parameters: {"destination": String}
        2. "search" - finds points of interest or categories (e.g. CNG, food, hospital) near location.
           Parameters: {"category": String, "bias": "near_me" | "along_route" | "near_destination"}
        3. "call" - calls a contact by name or dials a number.
           Parameters: {"name": String, "number": String?}
        4. "save_place" - saves a destination with a label.
           Parameters: {"name": String, "label": "home" | "work" | "college" | "custom"}
        5. "show_parking" - navigates to or shows current parking information.
           Parameters: {}
        6. "show_trips" - opens the recorded trip log history.
           Parameters: {}
        7. "avoid_road" - adds a road to the avoided list in route intelligence.
           Parameters: {"roadName": String}
        8. "prefer_road" - adds a road to the preferred list.
           Parameters: {"roadName": String}

        Output Format:
        Return a single JSON object. Do not wrap it in markdown code blocks. The JSON must contain:
        {
          "explanation": "Short, clear response to display to the user explaining what you are doing.",
          "toolCall": {
            "name": "navigate" | "search" | "call" | "save_place" | "show_parking" | "show_trips" | "avoid_road" | "prefer_road" | "none",
            "parameters": {}
          },
          "needsConfirmation": true | false
        }
        """

        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": query]
        ]

        let requestBody: [String: Any] = [
            "model": modelName,
            "messages": messages,
            "temperature": 0.2,
            "max_tokens": 300
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: requestBody) else {
            conversationHistory.append(ChatMessage(role: "assistant", content: "Error preparing coordinator request."))
            return
        }
        request.httpBody = httpBody

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                conversationHistory.append(ChatMessage(role: "assistant", content: "NVIDIA API request failed. Using local deterministic fallback parser."))
                localFallbackParser(query, viewModel: viewModel)
                return
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                conversationHistory.append(ChatMessage(role: "assistant", content: "Error decoding coordinator response. Using local parser."))
                localFallbackParser(query, viewModel: viewModel)
                return
            }

            parseAndExecute(content, viewModel: viewModel)
        } catch {
            conversationHistory.append(ChatMessage(role: "assistant", content: "Connection timeout. Using local fallback parser."))
            localFallbackParser(query, viewModel: viewModel)
        }
    }

    private func parseAndExecute(_ content: String, viewModel: DashboardViewModel) {
        // Strip markdown backticks if returned by the LLM
        var cleanContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanContent.hasPrefix("```") {
            cleanContent = cleanContent.components(separatedBy: "\n")
                .filter { !$0.hasPrefix("```") }
                .joined(separator: "\n")
        }

        guard let data = cleanContent.data(using: .utf8),
              let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let explanation = result["explanation"] as? String else {
            conversationHistory.append(ChatMessage(role: "assistant", content: "Could not parse structured intent. Here is the response: " + content))
            return
        }

        conversationHistory.append(ChatMessage(role: "assistant", content: explanation))

        guard let toolCall = result["toolCall"] as? [String: Any],
              let toolName = toolCall["name"] as? String,
              toolName != "none",
              let params = toolCall["parameters"] as? [String: Any] else {
            return
        }

        let needsConfirmation = result["needsConfirmation"] as? Bool ?? false

        executeTool(name: toolName, parameters: params, needsConfirmation: needsConfirmation, viewModel: viewModel)
    }

    private func executeTool(name: String, parameters: [String: Any], needsConfirmation: Bool, viewModel: DashboardViewModel) {
        switch name {
        case "navigate":
            guard let dest = parameters["destination"] as? String else { return }
            let action = {
                viewModel.destinationQuery = dest
                viewModel.searchDestinations()
                viewModel.selectSection(.map)
            }
            if needsConfirmation {
                pendingAction = PendingAction(title: "Confirm Route Change", message: "Do you want to navigate to \(dest)?", onConfirm: action)
            } else {
                action()
            }
        case "search":
            guard let category = parameters["category"] as? String else { return }
            viewModel.destinationQuery = category
            viewModel.searchDestinations()
            viewModel.selectSection(.map)
        case "call":
            guard let contactName = parameters["name"] as? String else { return }
            let number = parameters["number"] as? String
            
            // Search locally for the contact matching name
            if let matched = viewModel.nativeContacts.first(where: { $0.displayName.localizedCaseInsensitiveContains(contactName) }),
               let phone = matched.phoneNumbers.first?.number {
                let action = {
                    viewModel.call(number: phone, contactId: matched.id)
                }
                pendingAction = PendingAction(title: "Confirm Call", message: "Call \(matched.displayName) (\(phone))?", onConfirm: action)
            } else if let number {
                let action = {
                    viewModel.call(number: number, contactId: nil)
                }
                pendingAction = PendingAction(title: "Confirm Call", message: "Call \(contactName) at \(number)?", onConfirm: action)
            } else {
                conversationHistory.append(ChatMessage(role: "assistant", content: "I couldn't find a phone number for \(contactName). Please provide a number or check your contacts list."))
            }
        case "save_place":
            guard let name = parameters["name"] as? String,
                  let labelStr = parameters["label"] as? String,
                  let coord = viewModel.currentCoordinate else { return }
            
            let label: SavedPlaceLabel = switch labelStr {
            case "home": .home
            case "work": .work
            case "college": .college
            default: .custom
            }
            
            let action = {
                viewModel.savePlace(name: name, address: "Current Location", coordinate: coord, label: label)
            }
            pendingAction = PendingAction(title: "Save Place", message: "Save your current location as \(name) (\(labelStr))?", onConfirm: action)
        case "show_parking":
            viewModel.navigateToParking()
            viewModel.selectSection(.map)
        case "show_trips":
            viewModel.selectSection(.map)
        case "avoid_road":
            guard let roadName = parameters["roadName"] as? String else { return }
            let action = {
                viewModel.avoidRoad(roadName)
            }
            pendingAction = PendingAction(title: "Avoid Road", message: "Avoid \(roadName) in route intelligence planning?", onConfirm: action)
        case "prefer_road":
            guard let roadName = parameters["roadName"] as? String else { return }
            let action = {
                viewModel.preferRoad(roadName)
            }
            pendingAction = PendingAction(title: "Prefer Road", message: "Prefer \(roadName) in route intelligence planning?", onConfirm: action)
        default:
            break
        }
    }

    private func localFallbackParser(_ query: String, viewModel: DashboardViewModel) {
        let command = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        if command.contains("take me to") || command.contains("navigate to") || command.contains("go to") {
            let dest = query.replacingOccurrences(of: "take me to", with: "", options: .caseInsensitive, range: nil)
                .replacingOccurrences(of: "navigate to", with: "", options: .caseInsensitive, range: nil)
                .replacingOccurrences(of: "go to", with: "", options: .caseInsensitive, range: nil)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            conversationHistory.append(ChatMessage(role: "assistant", content: "Navigating to \(dest)…"))
            viewModel.destinationQuery = dest
            viewModel.searchDestinations()
            viewModel.selectSection(.map)
        } else if command.contains("call ") {
            let contactName = query.replacingOccurrences(of: "call", with: "", options: .caseInsensitive, range: nil)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            if let matched = viewModel.nativeContacts.first(where: { $0.displayName.localizedCaseInsensitiveContains(contactName) }),
               let phone = matched.phoneNumbers.first?.number {
                let action = {
                    viewModel.call(number: phone, contactId: matched.id)
                }
                pendingAction = PendingAction(title: "Confirm Call", message: "Call \(matched.displayName) (\(phone))?", onConfirm: action)
                conversationHistory.append(ChatMessage(role: "assistant", content: "Preparing call to \(matched.displayName)…"))
            } else {
                conversationHistory.append(ChatMessage(role: "assistant", content: "I couldn't find \(contactName) in your native iPad contacts directory."))
            }
        } else if command.contains("cng") || command.contains("c.n.g") {
            conversationHistory.append(ChatMessage(role: "assistant", content: "Searching for CNG fuel stations nearby…"))
            viewModel.destinationQuery = "CNG"
            viewModel.searchDestinations()
            viewModel.selectSection(.map)
        } else if command.contains("parking") {
            conversationHistory.append(ChatMessage(role: "assistant", content: "Showing parking location details…"))
            viewModel.selectSection(.map)
        } else {
            conversationHistory.append(ChatMessage(role: "assistant", content: "I parsed your request: \"\(query)\". However, I need configuration to execute complex planning tasks. Try commands like 'take me to [destination]' or 'call [contact name]'."))
        }
    }
}
