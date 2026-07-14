import Foundation
import CoreLocation
import KalpanaDriveCore

// --- Phase 13 Typed Structures ---
struct AssistantRequest: Codable {
    let query: String
    let context: AssistantContext
}

struct AssistantContext: Codable {
    let gpsAccuracy: String
    let currentSpeed: String
    let activeDestination: String
    let savedPlaces: [String]
}

struct AssistantToolDefinition: Codable {
    let name: String
    let description: String
}

enum AssistantToolName: String, Codable, CaseIterable {
    case navigate
    case search
    case call
    case savePlace = "save_place"
    case showParking = "show_parking"
    case showTrips = "show_trips"
    case avoidRoad = "avoid_road"
    case preferRoad = "prefer_road"
    case none
}

struct AssistantToolCall: Codable {
    let name: AssistantToolName
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

enum AssistantToolStatus: String, Codable {
    case awaitingConfirmation
    case started
    case completed
    case unavailable
    case failed
}

struct AssistantToolResult: Codable {
    let status: AssistantToolStatus
    let userFacingMessage: String
    let technicalReason: String?
    let resultingEntityId: String?
}

struct AssistantModelResponse: Codable {
    let explanation: String
    let toolCall: AssistantToolCall?
    let needsConfirmation: Bool?
}

struct AssistantPendingAction {
    let title: String
    let message: String
    let onConfirm: () -> Void
    let onReject: () -> Void
}

@MainActor
final class AICoordinator: ObservableObject {
    @Published var conversationHistory: [ChatMessage] = []
    @Published var isProcessing = false
    @Published var pendingAction: AssistantPendingAction?

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

    struct ConversationalContext {
        var lastMatchedContacts: [KalpanaContact] = []
        var lastMatchedSearchPlaces: [String] = []
    }

    var conversationalContext = ConversationalContext()

    private var apiKey: String {
        KeychainHelper.shared.loadApiKey() ?? ""
    }
    private let endpoint = "https://integrate.api.nvidia.com/v1/chat/completions"
    private let modelName = "meta/llama-3.1-8b-instruct"

    func clearHistory() {
        conversationHistory = []
        pendingAction = nil
        conversationalContext = ConversationalContext()
    }

    func processUserRequest(_ query: String, viewModel: DashboardViewModel) async {
        _ = await processQuery(query, viewModel: viewModel, isSpoken: false)
    }

    func processQuery(_ query: String, viewModel: DashboardViewModel, isSpoken: Bool) async -> String {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }

        if !isSpoken {
            conversationHistory.append(ChatMessage(role: "user", content: query))
        }
        isProcessing = true
        defer { isProcessing = false }

        // Check if API key is not configured or in localOnlyMode
        if KeychainHelper.shared.localOnlyMode || apiKey.isEmpty {
            let response = "AI provider not configured — local commands remain available."
            if !isSpoken {
                conversationHistory.append(ChatMessage(role: "assistant", content: response))
            }
            let fallbackResult = localFallbackParser(query, viewModel: viewModel)
            return fallbackResult.isEmpty ? response : fallbackResult
        }

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
            let errorMsg = "Error preparing coordinator request."
            conversationHistory.append(ChatMessage(role: "assistant", content: errorMsg))
            return errorMsg
        }
        request.httpBody = httpBody

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let fallbackMsg = "NVIDIA API request failed. Using local deterministic fallback parser."
                conversationHistory.append(ChatMessage(role: "assistant", content: fallbackMsg))
                return localFallbackParser(query, viewModel: viewModel)
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                let errDecodeMsg = "Error decoding coordinator response. Using local parser."
                conversationHistory.append(ChatMessage(role: "assistant", content: errDecodeMsg))
                return localFallbackParser(query, viewModel: viewModel)
            }

            return parseAndExecute(content, viewModel: viewModel)
        } catch {
            let timeoutMsg = "Connection timeout. Using local fallback parser."
            conversationHistory.append(ChatMessage(role: "assistant", content: timeoutMsg))
            return localFallbackParser(query, viewModel: viewModel)
        }
    }

    private func parseAndExecute(_ content: String, viewModel: DashboardViewModel) -> String {
        var cleanContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanContent.hasPrefix("```") {
            cleanContent = cleanContent.components(separatedBy: "\n")
                .filter { !$0.hasPrefix("```") }
                .joined(separator: "\n")
        }

        guard let data = cleanContent.data(using: .utf8),
              let modelResponse = try? JSONDecoder().decode(AssistantModelResponse.self, from: data) else {
            let errText = "Could not parse structured intent: " + content
            conversationHistory.append(ChatMessage(role: "assistant", content: errText))
            return errText
        }

        conversationHistory.append(ChatMessage(role: "assistant", content: modelResponse.explanation))

        if let tool = modelResponse.toolCall {
            let executor = AssistantToolExecutor(viewModel: viewModel)
            let result = executor.execute(toolCall: tool) { [weak self] confirmMsg, confirmAction in
                self?.pendingAction = AssistantPendingAction(
                    title: "Confirm Action",
                    message: confirmMsg,
                    onConfirm: confirmAction,
                    onReject: {}
                )
            }
            return result.userFacingMessage
        }

        return modelResponse.explanation
    }

    private func localFallbackParser(_ query: String, viewModel: DashboardViewModel) -> String {
        let command = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Conversational Context follow-up handling
        if command.contains("use the first") || command.contains("use the second") || command.contains("call the first") || command.contains("call the second") {
            let isSecond = command.contains("second")
            let index = isSecond ? 1 : 0
            if !conversationalContext.lastMatchedContacts.isEmpty {
                let contacts = conversationalContext.lastMatchedContacts
                if index < contacts.count {
                    let contact = contacts[index]
                    let number = contact.phoneNumbers.first?.number ?? ""
                    let destName = contact.displayName
                    let action = { [weak viewModel] in
                        guard let viewModel = viewModel else { return }
                        viewModel.call(number: number, contactId: contact.id)
                    }
                    self.pendingAction = AssistantPendingAction(
                        title: "Confirm Call",
                        message: "Opening phone dialer to call \(destName) at \(number)?",
                        onConfirm: action,
                        onReject: {}
                    )
                    let msg = "Confirm call to \(destName)?"
                    conversationHistory.append(ChatMessage(role: "assistant", content: msg))
                    return msg
                }
            }
        }

        if command.contains("take me to") || command.contains("navigate to") || command.contains("go to") {
            let dest = query.replacingOccurrences(of: "take me to", with: "", options: .caseInsensitive, range: nil)
                .replacingOccurrences(of: "navigate to", with: "", options: .caseInsensitive, range: nil)
                .replacingOccurrences(of: "go to", with: "", options: .caseInsensitive, range: nil)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let toolCall = AssistantToolCall(name: .navigate, parameters: AssistantToolParameters(destination: dest, category: nil, bias: nil, name: nil, number: nil, label: nil, roadName: nil))
            let executor = AssistantToolExecutor(viewModel: viewModel)
            let result = executor.execute(toolCall: toolCall) { [weak self] confirmMsg, confirmAction in
                self?.pendingAction = AssistantPendingAction(
                    title: "Confirm Route Change",
                    message: confirmMsg,
                    onConfirm: confirmAction,
                    onReject: {}
                )
            }
            conversationHistory.append(ChatMessage(role: "assistant", content: result.userFacingMessage))
            return result.userFacingMessage

        } else if command.contains("call ") {
            let contactName = query.replacingOccurrences(of: "call", with: "", options: .caseInsensitive, range: nil)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let toolCall = AssistantToolCall(name: .call, parameters: AssistantToolParameters(destination: nil, category: nil, bias: nil, name: contactName, number: nil, label: nil, roadName: nil))
            let executor = AssistantToolExecutor(viewModel: viewModel)
            let result = executor.execute(toolCall: toolCall) { [weak self] confirmMsg, confirmAction in
                self?.pendingAction = AssistantPendingAction(
                    title: "Confirm Call",
                    message: confirmMsg,
                    onConfirm: confirmAction,
                    onReject: {}
                )
            }
            conversationHistory.append(ChatMessage(role: "assistant", content: result.userFacingMessage))
            return result.userFacingMessage

        } else if command.contains("cng") || command.contains("c.n.g") {
            let toolCall = AssistantToolCall(name: .search, parameters: AssistantToolParameters(destination: nil, category: "CNG", bias: nil, name: nil, number: nil, label: nil, roadName: nil))
            let executor = AssistantToolExecutor(viewModel: viewModel)
            let result = executor.execute(toolCall: toolCall) { _, _ in }
            conversationHistory.append(ChatMessage(role: "assistant", content: result.userFacingMessage))
            return result.userFacingMessage

        } else if command.contains("parking") {
            let toolCall = AssistantToolCall(name: .showParking, parameters: AssistantToolParameters(destination: nil, category: nil, bias: nil, name: nil, number: nil, label: nil, roadName: nil))
            let executor = AssistantToolExecutor(viewModel: viewModel)
            let result = executor.execute(toolCall: toolCall) { _, _ in }
            conversationHistory.append(ChatMessage(role: "assistant", content: result.userFacingMessage))
            return result.userFacingMessage

        } else if command.contains("trip") {
            let toolCall = AssistantToolCall(name: .showTrips, parameters: AssistantToolParameters(destination: nil, category: nil, bias: nil, name: nil, number: nil, label: nil, roadName: nil))
            let executor = AssistantToolExecutor(viewModel: viewModel)
            let result = executor.execute(toolCall: toolCall) { _, _ in }
            conversationHistory.append(ChatMessage(role: "assistant", content: result.userFacingMessage))
            return result.userFacingMessage

        } else {
            let fallbackText = "I parsed your request: \"\(query)\". However, I need configuration to execute complex planning tasks. Try commands like 'take me to [destination]' or 'call [contact name]'."
            conversationHistory.append(ChatMessage(role: "assistant", content: fallbackText))
            return fallbackText
        }
    }

    func confirmAction() {
        pendingAction?.onConfirm()
        pendingAction = nil
    }

    func rejectAction() {
        pendingAction?.onReject()
        pendingAction = nil
    }

    func testConnection(with key: String) async -> (success: Bool, message: String) {
        guard !key.isEmpty else {
            return (false, "Key cannot be empty.")
        }
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let messages = [
            ["role": "user", "content": "hello"]
        ]
        let requestBody: [String: Any] = [
            "model": modelName,
            "messages": messages,
            "max_tokens": 5
        ]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: requestBody) else {
            return (false, "Error preparing test request.")
        }
        request.httpBody = httpBody

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    return (true, "Connection test succeeded!")
                } else {
                    return (false, "Test failed. Status code: \(httpResponse.statusCode)")
                }
            }
            return (false, "Invalid response type.")
        } catch {
            return (false, "Connection error: \(error.localizedDescription)")
        }
    }
}
