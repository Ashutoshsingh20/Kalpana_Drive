import SwiftUI

struct VoiceAssistantOverlay: View {
    @ObservedObject var coordinator: VoiceAssistantCoordinator
    let onKeyboardTap: () -> Void

    var body: some View {
        if coordinator.state != .idle {
            VStack(spacing: 16) {
                // Header (Icon + State)
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.15))
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: "sparkles")
                            .font(.title3)
                            .foregroundStyle(.blue)
                            .symbolEffect(.pulse, options: .repeating, value: coordinator.state == .thinking)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Kalpana Assistant")
                            .font(.headline)
                        Text(stateDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()

                    // Keyboard Button
                    Button(action: onKeyboardTap) {
                        Image(systemName: "keyboard")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 4)

                    // Close Button
                    Button(action: { coordinator.cancelListening() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                // Transcript or Assistant Response
                VStack(alignment: .leading, spacing: 8) {
                    if !coordinator.partialTranscript.isEmpty {
                        Text(coordinator.partialTranscript)
                            .font(.body.italic())
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if !coordinator.assistantResponse.isEmpty {
                        Text(coordinator.assistantResponse)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(12)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(10)

                // Interactive Waveform representation
                if coordinator.state == .listening || coordinator.state == .detectingSpeech {
                    HStack(spacing: 4) {
                        ForEach(0..<12) { i in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.blue)
                                .frame(width: 4, height: waveHeight(for: i))
                        }
                    }
                    .frame(height: 36)
                }

                // Confirm / Cancel Actions for pending operations
                if case .awaitingConfirmation(let message, let confirmAction) = coordinator.state {
                    VStack(spacing: 10) {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        
                        HStack(spacing: 16) {
                            Button("Cancel") {
                                coordinator.rejectAction()
                            }
                            .buttonStyle(.bordered)

                            Button("Confirm") {
                                coordinator.confirmAction(action: confirmAction)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
            .padding(18)
            .background(.ultraThinMaterial)
            .cornerRadius(18)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1.5)
            )
            .frame(maxWidth: 420)
            .shadow(color: Color.black.opacity(0.15), radius: 10, y: 5)
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    private var stateDescription: String {
        switch coordinator.state {
        case .idle: return "Idle"
        case .requestingPermission: return "Requesting Permissions…"
        case .listening: return "Listening for voice command…"
        case .detectingSpeech: return "Speaking…"
        case .transcribing: return "Transcribing voice…"
        case .thinking: return "Thinking…"
        case .awaitingConfirmation: return "Awaiting Confirmation…"
        case .speaking: return "Speaking Response…"
        case .interrupted: return "Interrupted"
        case .unavailable(let reason): return "Unavailable: \(reason)"
        case .failed(let err): return "Failed: \(err)"
        }
    }

    private func waveHeight(for index: Int) -> CGFloat {
        // Convert dB micLevel (e.g. -100 to 0) to standard height range
        let level = max(0, coordinator.micLevel + 80) // shift so 0-80 range
        let normalized = CGFloat(level / 80.0)
        let baseHeight: CGFloat = 6.0
        let randomFactor = CGFloat.random(in: 0.7...1.3)
        return max(baseHeight, baseHeight + normalized * 30.0 * randomFactor)
    }
}
