import AVFoundation
import Foundation

@MainActor
final class AssistantSpeechService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var isSpeaking = false

    private let synthesizer = AVSpeechSynthesizer()
    var onSpeechFinished: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, language: SpeechRecognitionService.LanguageMode) {
        stop()
        
        let utterance = AVSpeechUtterance(string: text)
        let localeId = language.localeIdentifier
        utterance.voice = AVSpeechSynthesisVoice(language: localeId)
        utterance.rate = 0.48 // Adjustable speaking rate
        utterance.pitchMultiplier = 1.0

        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
    }
}

extension AssistantSpeechService {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            isSpeaking = false
            onSpeechFinished?()
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            isSpeaking = false
        }
    }
}
