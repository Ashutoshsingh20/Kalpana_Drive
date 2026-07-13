import Foundation

struct AssistantMessage: Identifiable, Codable {
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

@MainActor
final class AssistantConversationStore: ObservableObject {
    @Published var messages: [AssistantMessage] = []

    func addMessage(role: String, content: String) {
        messages.append(AssistantMessage(role: role, content: content))
    }

    func clear() {
        messages = []
    }
}
