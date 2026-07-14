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
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10))

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

                if coordinator.state == .speaking {
                    Button(action: {
                        coordinator.cancelListening()
                    }) {
                        Label("Tap to interrupt", systemImage: "hand.raised.fill")
                            .font(.caption.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.red.opacity(0.15))
                            .foregroundStyle(.red)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                // Confirm / Cancel Actions for pending operations
                if coordinator.state == .awaitingConfirmation, let pending = coordinator.pendingAction {
                    VStack(spacing: 10) {
                        Text(pending.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        
                        HStack(spacing: 16) {
                            Button("Cancel") {
                                coordinator.rejectAction()
                            }
                            .buttonStyle(.bordered)

                            Button("Confirm") {
                                coordinator.confirmAction()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
            .padding(18)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
            .frame(maxWidth: 420)
            .shadow(color: Color.blue.opacity(0.18), radius: 24, y: 8)
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
        // Convert dB micLevel (e.g. -80 to 0) to standard height range
        let level = max(0, coordinator.micLevel + 80) // shift so 0-80 range
        let normalized = CGFloat(level / 80.0)
        let baseHeight: CGFloat = 6.0
        
        // Use a deterministic wave pattern based on the index to create a nice symmetric envelope
        let factor = sin(Double(index) * Double.pi / 11.0)
        let envelope = CGFloat(factor)
        
        return max(baseHeight, baseHeight + normalized * 30.0 * envelope)
    }
}
