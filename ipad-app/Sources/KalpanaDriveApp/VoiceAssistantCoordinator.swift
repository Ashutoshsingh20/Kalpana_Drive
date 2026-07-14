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
    case awaitingConfirmation
    case speaking
    case interrupted
    case unavailable(String)
    case failed(String)
}

@MainActor
final class VoiceAssistantCoordinator: ObservableObject {
    @Published var state: VoiceAssistantState = .idle {
        willSet {
            #if DEBUG
            validateTransition(from: state, to: newValue)
            #endif
        }
    }
    @Published var partialTranscript: String = ""
    @Published var finalTranscript: String = ""
    @Published var assistantResponse: String = ""
    @Published var micLevel: Float = 0.0
    @Published var pendingAction: AssistantPendingAction?

    let micPermission = MicrophonePermissionService()
    let speechRecognition = SpeechRecognitionService()
    let vad = VoiceActivityDetector()
    let speechService = AssistantSpeechService()
    
    private let browser: YouTubeMusicBrowserController
    private var musicCoordinator: MusicSessionCoordinator?
    private var viewModel: DashboardViewModel?

    private let audioEngine = AVAudioEngine()
    private var hasSubmitted = false

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
        self.viewModel = viewModel
    }

    func toggleListening() {
        if state == .listening || state == .detectingSpeech {
            cancelListening()
        } else {
            startListening()
        }
    }

    func startListening() {
        guard state == .idle || state == .interrupted || state == .speaking else { return }

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
        hasSubmitted = false
        state = .listening

        do {
            try configureAudioEngine()
            try speechRecognition.beginRecognition(
                onTranscript: { [weak self] text, isFinal in
                    guard let self else { return }
                    self.partialTranscript = text
                    self.state = .detectingSpeech
                    
                    if isFinal {
                        self.stopListeningAndProcess(withTranscript: text)
                    }
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
            
            // Forward buffer to SpeechRecognitionService and VoiceActivityDetector
            Task { @MainActor in
                self.speechRecognition.append(buffer)
                self.micLevel = self.vad.audioLevel

                // Handle barge-in (interruption during TTS)
                if self.state == .speaking {
                    let rms = self.calculateRMS(buffer)
                    if rms > 0.12 { // Calibrated voice threshold
                        self.speechService.stop()
                        self.state = .interrupted
                        self.beginListeningPipeline()
                        return
                    }
                }

                if self.state == .listening || self.state == .detectingSpeech {
                    let isSilent = self.vad.analyzeBuffer(buffer)
                    if isSilent && !self.partialTranscript.isEmpty {
                        self.stopListeningAndProcess(withTranscript: self.partialTranscript)
                    }
                }
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    private func stopAudioEngine() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
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

    private func stopListeningAndProcess(withTranscript transcript: String) {
        guard !hasSubmitted else { return }
        hasSubmitted = true
        
        stopAudioEngine()
        speechRecognition.finishRecognition()
        
        finalTranscript = transcript
        state = .thinking

        guard !finalTranscript.isEmpty else {
            state = .idle
            musicCoordinator?.restoreAfterVoiceDeactivation()
            return
        }

        // Add user query to context history
        viewModel?.aiCoordinator.conversationHistory.append(AICoordinator.ChatMessage(role: "user", content: finalTranscript))

        // Execute AI parsing on the unified AICoordinator
        Task {
            guard let viewModel = self.viewModel else { return }
            let response = await viewModel.aiCoordinator.processQuery(finalTranscript, viewModel: viewModel, isSpoken: true)
            handleAIResponse(response)
        }
    }

    private func handleAIResponse(_ text: String) {
        assistantResponse = text

        // Check if there is a pending action on AICoordinator
        if let pending = viewModel?.aiCoordinator.pendingAction {
            self.pendingAction = AssistantPendingAction(
                title: pending.title,
                message: pending.message,
                onConfirm: { [weak self] in
                    guard let self else { return }
                    self.viewModel?.aiCoordinator.confirmAction()
                    self.state = .idle
                    self.musicCoordinator?.restoreAfterVoiceDeactivation()
                },
                onReject: { [weak self] in
                    guard let self else { return }
                    self.viewModel?.aiCoordinator.rejectAction()
                    self.state = .idle
                    self.musicCoordinator?.restoreAfterVoiceDeactivation()
                }
            )
            state = .awaitingConfirmation
            speakResult(pending.message)
        } else {
            speakResult(text)
        }
    }

    func confirmAction() {
        pendingAction?.onConfirm()
        pendingAction = nil
        state = .idle
        musicCoordinator?.restoreAfterVoiceDeactivation()
    }

    func rejectAction() {
        pendingAction?.onReject()
        pendingAction = nil
        state = .idle
        musicCoordinator?.restoreAfterVoiceDeactivation()
    }

    private func speakResult(_ text: String) {
        state = .speaking
        speechService.speak(text, language: speechRecognition.selectedLanguage)
    }

    func cancelListening() {
        stopAudioEngine()
        speechRecognition.cancelRecognition()
        speechService.stop()
        pendingAction = nil
        state = .idle
        musicCoordinator?.restoreAfterVoiceDeactivation()
    }

    private func handleError(_ error: Error) {
        stopAudioEngine()
        speechRecognition.cancelRecognition()
        state = .failed(error.localizedDescription)
        musicCoordinator?.restoreAfterVoiceDeactivation()
    }

    #if DEBUG
    private func validateTransition(from oldState: VoiceAssistantState, to newState: VoiceAssistantState) {
        switch (oldState, newState) {
        case (.idle, .requestingPermission),
             (.requestingPermission, .listening), (.requestingPermission, .unavailable(_)),
             (.listening, .detectingSpeech), (.listening, .thinking), (.listening, .idle),
             (.detectingSpeech, .thinking), (.detectingSpeech, .idle),
             (.thinking, .awaitingConfirmation), (.thinking, .speaking), (.thinking, .idle),
             (.awaitingConfirmation, .idle),
             (.speaking, .idle), (.speaking, .interrupted),
             (.interrupted, .listening), (.interrupted, .idle),
             (.failed(_), .idle), (.unavailable(_), .idle),
             (_, .idle), (_, .failed(_)):
            break
        default:
            print("VoiceAssistantState: transition from \(oldState) to \(newState)")
        }
    }
    #endif
}
