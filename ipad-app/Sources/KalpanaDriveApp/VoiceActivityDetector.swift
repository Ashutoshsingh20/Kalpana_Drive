import AVFoundation
import Foundation

@MainActor
final class VoiceActivityDetector: ObservableObject {
    @Published var audioLevel: Float = 0.0

    private var silenceStartTime: Date?
    private let silenceThreshold: Float = -45.0 // dB
    private let silenceDurationNeeded: TimeInterval = 2.0 // seconds

    func reset() {
        silenceStartTime = nil
        audioLevel = 0.0
    }

    /// Analyzes a PCM buffer and checks if silence is detected.
    /// Returns true if the user has been silent for the required duration.
    func analyzeBuffer(_ buffer: AVAudioPCMBuffer) -> Bool {
        guard let channelData = buffer.floatChannelData else { return false }
        
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        
        var maxVal: Float = 0.0
        for channel in 0..<channelCount {
            let data = channelData[channel]
            for frame in 0..<frameLength {
                let val = abs(data[frame])
                if val > maxVal {
                    maxVal = val
                }
            }
        }
        
        // Convert to dBFS
        let db = maxVal > 0.00001 ? 20 * log10(maxVal) : -100.0
        audioLevel = db

        if db < silenceThreshold {
            if let start = silenceStartTime {
                let duration = Date().timeIntervalSince(start)
                if duration >= silenceDurationNeeded {
                    return true
                }
            } else {
                silenceStartTime = Date()
            }
        } else {
            silenceStartTime = nil
        }
        
        return false
    }
}
