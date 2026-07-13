import AVFoundation
import Speech
import Combine
import Foundation

enum VoiceAssistantState: Equatable {
    case idle
    case requestingPermission
    case listening
    case detectingSpeech
    case transcribing
    case thinking
    case awaitingConfirmation(String, () -> Void)
    case speaking(String)
    case interrupted
    case unavailable(String)
    case failed(String)

    static func == (lhs: VoiceAssistantState, rhs: VoiceAssistantState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.requestingPermission, .requestingPermission): return true
        case (.listening, .listening): return true
        case (.detectingSpeech, .detectingSpeech): return true
        case (.transcribing, .transcribing): return true
        case (.thinking, .thinking): return true
        case (.interrupted, .interrupted): return true
        case (.awaitingConfirmation(let a, _), .awaitingConfirmation(let b, _)): return a == b
        case (.speaking(let a), .speaking(let b)): return a == b
        case (.unavailable(let a), .unavailable(let b)): return a == b
        case (.failed(let a), .failed(let b)): return a == b
        default: return false
        }
    }
}

@MainActor
final class VoiceAssistantCoordinator: ObservableObject {
    @Published var state: VoiceAssistantState = .idle
    @Published var partialTranscript: String = ""
    @Published var finalTranscript: String = ""
    @Published var assistantResponse: String = ""
    @Published var micLevel: Float = 0.0

    let micPermission = MicrophonePermissionService()
    let speechRecognition = SpeechRecognitionService()
    let vad = VoiceActivityDetector()
    let conversationStore = AssistantConversationStore()
    let speechService = AssistantSpeechService()
    
    private let browser: YouTubeMusicBrowserController
    private var musicCoordinator: MusicSessionCoordinator?
    private var toolExecutor: AssistantToolExecutor?

    private let audioEngine = AVAudioEngine()
    private var isEngineConfigured = false

    init(browser: YouTubeMusicBrowserController) {
        self.browser = browser
        self.musicCoordinator = MusicSessionCoordinator(browser: browser)
        
        self.speechService.onSpeechFinished = { [weak self] in
            guard let self else { return }
            self.musicCoordinator?.restoreAfterVoiceDeactivation()
            self.state = .idle
        }
    }

    func setViewModel(_ viewModel: DashboardViewModel) {
        self.toolExecutor = AssistantToolExecutor(viewModel: viewModel)
    }

    func toggleListening() {
        if state == .listening || state == .detectingSpeech {
            cancelListening()
        } else {
            startListening()
        }
    }

    func startListening() {
        guard state == .idle || state == .interrupted || state == .speaking("") else { return }

        state = .requestingPermission
        Task {
            let micGranted = await micPermission.requestPermission()
            let speechGranted = await speechRecognition.requestAuthorization()

            guard micGranted && speechGranted else {
                state = .unavailable("Microphone or Speech Recognition permission is denied. Enable them in Settings.")
                return
            }

            beginListeningPipeline()
        }
    }

    private func beginListeningPipeline() {
        speechService.stop()
        musicCoordinator?.prepareForVoiceActivation()
        vad.reset()
        
        partialTranscript = ""
        finalTranscript = ""
        state = .listening

        do {
            try configureAudioEngine()
            try speechRecognition.startRecognition(
                audioEngine: audioEngine,
                onTranscript: { [weak self] text, isFinal in
                    guard let self else { return }
                    self.partialTranscript = text
                    self.state = .detectingSpeech
                },
                onError: { [weak self] error in
                    guard let self else { return }
                    self.handleError(error)
                }
            )
        } catch {
            handleError(error)
        }
    }

    private func configureAudioEngine() throws {
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            Task { @MainActor in
                self.micLevel = self.vad.audioLevel

                // Handle barge-in (interruption during TTS)
                if case .speaking = self.state {
                    let rms = self.calculateRMS(buffer)
                    if rms > 0.08 { // Decisive voice signal from user
                        self.speechService.stop()
                        self.state = .interrupted
                        self.beginListeningPipeline()
                        return
                    }
                }

                if self.state == .listening || self.state == .detectingSpeech {
                    let isSilent = self.vad.analyzeBuffer(buffer)
                    if isSilent {
                        self.stopListeningAndProcess()
                    }
                }
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    private func calculateRMS(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0.0 }
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        var sumSquares: Float = 0.0
        for channel in 0..<channelCount {
            let data = channelData[channel]
            for frame in 0..<frameLength {
                sumSquares += data[frame] * data[frame]
            }
        }
        return sqrt(sumSquares / Float(frameLength * channelCount))
    }

    private func stopListeningAndProcess() {
        speechRecognition.stopRecognition(audioEngine: audioEngine)
        finalTranscript = partialTranscript
        state = .thinking

        guard !finalTranscript.isEmpty else {
            state = .idle
            musicCoordinator?.restoreAfterVoiceDeactivation()
            return
        }

        conversationStore.addMessage(role: "user", content: finalTranscript)
        
        // Execute AI parsing
        Task {
            if let apiKey = KeychainHelper.shared.loadApiKey(), !apiKey.isEmpty {
                await processWithNvidiaNIM(finalTranscript)
            } else {
                processWithLocalFallback(finalTranscript)
            }
        }
    }

    private func processWithNvidiaNIM(_ query: String) async {
        let endpoint = "https://integrate.api.nvidia.com/v1/chat/completions"
        let modelName = "meta/llama-3.1-8b-instruct"
        
        let systemPrompt = """
        You are Kalpana Voice Assistant. Parse the user request.
        Respond with a JSON block:
        {
          "explanation": "Spoken text",
          "toolCall": {
            "name": "navigate" | "search" | "call" | "save_place" | "show_parking" | "show_trips" | "avoid_road" | "prefer_road",
            "parameters": { ... }
          },
          "needsConfirmation": true
        }
        """

        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(KeychainHelper.shared.loadApiKey() ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let messages = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": query]
        ]
        let body: [String: Any] = ["model": modelName, "messages": messages, "temperature": 0.1]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                processWithLocalFallback(query)
                return
            }

            let modelResponse = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
            if let firstMessage = modelResponse.choices.first?.message.content {
                var clean = firstMessage.trimmingCharacters(in: .whitespacesAndNewlines)
                if clean.hasPrefix("```") {
                    clean = clean.components(separatedBy: "\n").filter { !$0.hasPrefix("```") }.joined(separator: "\n")
                }
                if let decodedResult = try? JSONDecoder().decode(AssistantModelResponse.self, from: clean.data(using: .utf8)!) {
                    handleAIResponse(decodedResult)
                    return
                }
            }
            processWithLocalFallback(query)
        } catch {
            processWithLocalFallback(query)
        }
    }

    private func processWithLocalFallback(_ query: String) {
        let clean = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        var explanation = "I'm not sure how to help with that request."
        var toolCall: AssistantToolCall? = nil
        var needsConfirmation = false

        if clean.contains("take me to") || clean.contains("navigate to") || clean.contains("go to") {
            let dest = query.replacingOccurrences(of: "take me to", with: "", options: .caseInsensitive, range: nil)
                .replacingOccurrences(of: "navigate to", with: "", options: .caseInsensitive, range: nil)
                .replacingOccurrences(of: "go to", with: "", options: .caseInsensitive, range: nil)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            explanation = "Calculating route to \(dest)."
            toolCall = AssistantToolCall(name: "navigate", parameters: AssistantToolParameters(destination: dest, category: nil, bias: nil, name: nil, number: nil, label: nil, roadName: nil))
            needsConfirmation = true
        } else if clean.contains("cng") {
            explanation = "Searching for CNG fuel stations."
            toolCall = AssistantToolCall(name: "search", parameters: AssistantToolParameters(destination: nil, category: "CNG", bias: nil, name: nil, number: nil, label: nil, roadName: nil))
        } else if clean.contains("call") {
            let name = query.replacingOccurrences(of: "call", with: "", options: .caseInsensitive, range: nil).trimmingCharacters(in: .whitespacesAndNewlines)
            explanation = "Calling \(name)."
            toolCall = AssistantToolCall(name: "call", parameters: AssistantToolParameters(destination: nil, category: nil, bias: nil, name: name, number: nil, label: nil, roadName: nil))
            needsConfirmation = true
        } else if clean.contains("parking") {
            explanation = "Displaying your car's parking location."
            toolCall = AssistantToolCall(name: "show_parking", parameters: AssistantToolParameters(destination: nil, category: nil, bias: nil, name: nil, number: nil, label: nil, roadName: nil))
        }

        handleAIResponse(AssistantModelResponse(explanation: explanation, toolCall: toolCall, needsConfirmation: needsConfirmation))
    }

    private func handleAIResponse(_ res: AssistantModelResponse) {
        assistantResponse = res.explanation
        conversationStore.addMessage(role: "assistant", content: res.explanation)

        if let tool = res.toolCall {
            if res.needsConfirmation == true, let executor = toolExecutor {
                state = .awaitingConfirmation(res.explanation) {
                    _ = executor.execute(toolCall: tool) { _, confirmAction in
                        confirmAction()
                    }
                }
            } else if let executor = toolExecutor {
                let statusMsg = executor.execute(toolCall: tool) { _, confirmAction in
                    confirmAction()
                }
                speakResult(statusMsg)
            }
        } else {
            speakResult(res.explanation)
        }
    }

    func confirmAction(action: @escaping () -> Void) {
        action()
        state = .idle
        musicCoordinator?.restoreAfterVoiceDeactivation()
    }

    func rejectAction() {
        state = .idle
        musicCoordinator?.restoreAfterVoiceDeactivation()
    }

    private func speakResult(_ text: String) {
        state = .speaking(text)
        speechService.speak(text, language: speechRecognition.selectedLanguage)
    }

    func cancelListening() {
        speechRecognition.stopRecognition(audioEngine: audioEngine)
        speechService.stop()
        state = .idle
        musicCoordinator?.restoreAfterVoiceDeactivation()
    }

    private func handleError(_ error: Error) {
        state = .failed(error.localizedDescription)
        musicCoordinator?.restoreAfterVoiceDeactivation()
    }
}

// NIM API structures
struct ChatCompletionResponse: Codable {
    struct Choice: Codable {
        struct Message: Codable {
            let content: String
        }
        let message: Message
    }
    let choices: [Choice]
}
