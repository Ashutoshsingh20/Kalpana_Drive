import AVFoundation
import Foundation

@MainActor
final class MusicSessionCoordinator: ObservableObject {
    private let browser: YouTubeMusicBrowserController
    private var wasPlayingBeforeActivation = false
    
    @Published var errorMessage: String? = nil

    init(browser: YouTubeMusicBrowserController) {
        self.browser = browser
        setupNotifications()
        setupAudioSession()
    }

    private func setupNotifications() {
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
        center.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance()
        )
        center.addObserver(
            self,
            selector: #selector(handleMediaServicesReset),
            name: AVAudioSession.mediaServicesWereResetNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.allowBluetoothHFP, .allowAirPlay])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Failed to configure audio session: \(error.localizedDescription)"
        }
    }

    @objc private func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        Task { @MainActor in
            switch type {
            case .began:
                // System interrupted playback (e.g. phone call)
                await browser.pause()
            case .ended:
                if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                    if options.contains(.shouldResume) {
                        await browser.play()
                    }
                }
            @unknown default:
                break
            }
        }
    }

    @objc private func handleRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        Task { @MainActor in
            switch reason {
            case .oldDeviceUnavailable:
                // Audio route disconnected (e.g. headphones pulled out, bluetooth disconnected)
                // Pause to prevent audio leaking to iPad speaker unexpectedly
                await browser.pause()
            default:
                break
            }
        }
    }

    @objc private func handleMediaServicesReset() {
        Task { @MainActor in
            setupAudioSession()
        }
    }

    func prepareForVoiceActivation() {
        wasPlayingBeforeActivation = browser.isPlayerAvailable && browser.isPlaying
        if wasPlayingBeforeActivation {
            Task {
                await browser.pause()
            }
        }
        
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Failed to configure voice session: \(error.localizedDescription)"
        }
    }

    func restoreAfterVoiceDeactivation() {
        setupAudioSession()

        if wasPlayingBeforeActivation {
            Task {
                await browser.play()
                wasPlayingBeforeActivation = false
            }
        }
    }
}
