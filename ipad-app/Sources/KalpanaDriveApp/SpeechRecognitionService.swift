import Speech
import Foundation
import AVFoundation

@MainActor
final class SpeechRecognitionService: NSObject, ObservableObject {
    @Published var isAuthorized = false
    @Published var selectedLanguage: LanguageMode = .en_IN

    enum LanguageMode: String, CaseIterable, Identifiable {
        case en_IN = "English (India)"
        case hi_IN = "Hindi (India)"
        case hinglish = "Hinglish (Hybrid)"
        var id: Self { self }

        var localeIdentifier: String {
            switch self {
            case .en_IN, .hinglish: return "en-IN"
            case .hi_IN: return "hi-IN"
            }
        }
    }

    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    override init() {
        super.init()
        checkAuthorization()
        updateRecognizer()
    }

    func checkAuthorization() {
        let status = SFSpeechRecognizer.authorizationStatus()
        isAuthorized = (status == .authorized)
    }

    func requestAuthorization() async -> Bool {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        isAuthorized = (status == .authorized)
        return isAuthorized
    }

    func setLanguage(_ mode: LanguageMode) {
        selectedLanguage = mode
        updateRecognizer()
    }

    private func updateRecognizer() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: selectedLanguage.localeIdentifier))
    }

    func startRecognition(audioEngine: AVAudioEngine, onTranscript: @escaping @MainActor (String, Bool) -> Void, onError: @escaping @MainActor (Error) -> Void) throws {
        // Cancel any pending task
        cancelExistingTask()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(iOS 13.0, *), recognizer?.supportsOnDeviceRecognition == true {
            request.requiresOnDeviceRecognition = true
        } else {
            request.requiresOnDeviceRecognition = false
        }
        
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        
        // Remove tap to be safe before installing a new one
        inputNode.removeTap(onBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        recognitionTask = recognizer?.recognitionTask(with: request) { result, error in
            Task { @MainActor in
                if let result {
                    let text = result.bestTranscription.formattedString
                    let isFinal = result.isFinal
                    
                    // Apply optional Hinglish normalization
                    let processedText = self.applyHinglishNormalization(text)
                    onTranscript(processedText, isFinal)
                }
                if let error {
                    onError(error)
                }
            }
        }
    }

    func stopRecognition(audioEngine: AVAudioEngine) {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        cancelExistingTask()
    }

    private func cancelExistingTask() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
    }

    private func applyHinglishNormalization(_ text: String) -> String {
        guard selectedLanguage == .hinglish else { return text }
        // Simple map from phonetic Devnagari transcript segments to normalized Hindi/English words
        var output = text
        let map: [String: String] = [
            "cng": "CNG",
            "niet": "NIET",
            "college": "College",
            "call karo": "Call",
            "phone karo": "Call",
            "roko": "Stop",
            "gaana": "Music",
            "play karo": "Play"
        ]
        for (key, val) in map {
            output = output.replacingOccurrences(of: key, with: val, options: .caseInsensitive)
        }
        return output
    }
}
