import AVFoundation
import Foundation

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

        DispatchQueue.main.async { [weak self] in
            self?.isSpeaking = true
        }
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        DispatchQueue.main.async { [weak self] in
            self?.isSpeaking = false
        }
    }
}

extension AssistantSpeechService {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isSpeaking = false
            self.onSpeechFinished?()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            self?.isSpeaking = false
        }
    }
}
