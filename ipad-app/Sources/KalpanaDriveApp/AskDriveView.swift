import SwiftUI
import KalpanaDriveCore

struct AskDriveView: View {
    @ObservedObject var model: DashboardViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var userQuery = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Conversation Area
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 12) {
                            if model.aiCoordinator.conversationHistory.isEmpty {
                                welcomeBanner
                            } else {
                                ForEach(model.aiCoordinator.conversationHistory) { message in
                                    chatBubble(for: message)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .onChange(of: model.aiCoordinator.conversationHistory.count) { _, _ in
                        if let last = model.aiCoordinator.conversationHistory.last {
                            withAnimation {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Pending Actions / Confirmation Box
                if let pending = model.aiCoordinator.pendingAction {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(pending.title)
                            .font(.headline)
                            .foregroundStyle(.blue)
                        Text(pending.message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            Button("Confirm") {
                                pending.onConfirm()
                                model.aiCoordinator.pendingAction = nil
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Cancel", role: .cancel) {
                                model.aiCoordinator.pendingAction = nil
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding()
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Suggestions shortcuts
                if model.aiCoordinator.conversationHistory.isEmpty {
                    suggestionsSection
                }

                // Query Input Box
                HStack(spacing: 10) {
                    TextField("Ask Drive to navigate, call, or search…", text: $userQuery)
                        .textFieldStyle(.roundedBorder)
                        .font(.headline)
                        .submitLabel(.send)
                        .onSubmit(sendQuery)
                        .disabled(model.aiCoordinator.isProcessing)

                    if model.aiCoordinator.isProcessing {
                        ProgressView()
                            .padding(.horizontal, 8)
                    } else {
                        Button("Send") {
                            sendQuery()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(userQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(.top, 8)
            }
            .padding(18)
            .navigationTitle("Ask Drive — AI Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Clear Chat") {
                        model.aiCoordinator.clearHistory()
                    }
                }
            }
        }
    }

    private var welcomeBanner: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 54))
                .foregroundStyle(.blue)
                .padding(.top, 40)
            Text("Kalpana AI Assistant")
                .font(.title2.bold())
            Text("Ask Kalpana Drive to search destinations, plan routes, check your parking position, or make phone calls safely using natural language.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Suggested Actions").font(.caption.bold()).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    suggestionPill("Take me to NIET")
                    suggestionPill("Find CNG on the way")
                    suggestionPill("Where did we park?")
                    suggestionPill("Call Ashutosh")
                    suggestionPill("Avoid Noida Expressway")
                }
            }
        }
    }

    private func suggestionPill(_ text: String) -> some View {
        Button {
            userQuery = text
            sendQuery()
        } label: {
            Text(text)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.06))
                .cornerRadius(18)
        }
        .buttonStyle(.plain)
    }

    private func chatBubble(for message: AICoordinator.ChatMessage) -> some View {
        let isUser = message.role == "user"
        return HStack {
            if isUser { Spacer() }
            Text(message.content)
                .font(.body)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isUser ? Color.blue : Color.primary.opacity(0.08))
                .foregroundColor(isUser ? .white : .primary)
                .cornerRadius(12)
                .id(message.id)
            if !isUser { Spacer() }
        }
    }

    private func sendQuery() {
        let query = userQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        userQuery = ""
        model.askDrive(query: query)
    }
}
