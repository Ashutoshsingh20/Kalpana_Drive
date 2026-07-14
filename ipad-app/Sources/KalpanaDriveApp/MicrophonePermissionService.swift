import AVFoundation

@MainActor
final class MicrophonePermissionService: ObservableObject {
    @Published var isPermissionGranted = false

    init() {
        checkPermission()
    }

    func checkPermission() {
        let status = AVAudioApplication.shared.recordPermission
        isPermissionGranted = (status == .granted)
    }

    func requestPermission() async -> Bool {
        let granted = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        isPermissionGranted = granted
        return granted
    }
}
