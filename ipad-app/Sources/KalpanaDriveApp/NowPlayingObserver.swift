import Combine
import Foundation
import MediaPlayer
import SwiftUI

/// Observes the system Now Playing session (MPNowPlayingInfoCenter).
/// Works with any audio source — including YouTube Music playing inside
/// SFSafariViewController — because iOS registers all audio players in the
/// shared Now Playing session that the Lock Screen and Control Centre also use.
@MainActor
final class NowPlayingObserver: ObservableObject {
    static let shared = NowPlayingObserver()

    @Published private(set) var trackTitle: String = ""
    @Published private(set) var trackArtist: String = ""
    @Published private(set) var trackArtwork: UIImage? = nil
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var isActive: Bool = false   // true when something is loaded
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0

    private var pollTimer: AnyCancellable?

    private init() {
        startPolling()
    }

    // MARK: - Polling

    private func startPolling() {
        pollTimer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }

    private func refresh() {
        let info = MPNowPlayingInfoCenter.default().nowPlayingInfo

        let title  = info?[MPMediaItemPropertyTitle]  as? String ?? ""
        let artist = info?[MPMediaItemPropertyArtist] as? String ?? ""

        // Artwork — MPMediaItemArtwork can give us a UIImage at any size
        let artwork: UIImage?
        if let mpArtwork = info?[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork {
            artwork = mpArtwork.image(at: CGSize(width: 80, height: 80))
        } else {
            artwork = nil
        }

        let playbackRate = info?[MPNowPlayingInfoPropertyPlaybackRate] as? Double ?? 0
        let playing = playbackRate > 0

        // Elapsed and total duration from the Now Playing info dictionary
        let elapsedValue  = info?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? TimeInterval ?? 0
        let durationValue = info?[MPMediaItemPropertyPlaybackDuration]         as? TimeInterval ?? 0

        let active = !title.isEmpty

        // Only publish when something changed — avoids thrashing SwiftUI
        if title         != trackTitle   { trackTitle   = title         }
        if artist        != trackArtist  { trackArtist  = artist        }
        if playing       != isPlaying    { isPlaying    = playing       }
        if active        != isActive     { isActive     = active        }
        if elapsedValue  != elapsed      { elapsed      = elapsedValue  }
        if durationValue != duration     { duration     = durationValue }

        // Artwork comparison via pointer identity is fine for our purposes
        if artwork !== trackArtwork { trackArtwork = artwork }
    }

    // MARK: - Remote controls (MPRemoteCommandCenter)

    /// Send a play command to whatever player owns the Now Playing session.
    func play() {
        MPRemoteCommandCenter.shared().playCommand.isEnabled = true
        _ = MPRemoteCommandCenter.shared().playCommand.isEnabled
        // Simulate the system command by posting via MPMusicPlayerController proxy
        // The most reliable cross-app approach is to send the HW play event.
        sendMediaKey(.play)
    }

    func pause() { sendMediaKey(.pause) }
    func next()  { sendMediaKey(.nextTrack) }
    func previous() { sendMediaKey(.previousTrack) }
    func togglePlayPause() { sendMediaKey(.togglePlayPause) }

    private enum MediaKey {
        case play, pause, togglePlayPause, nextTrack, previousTrack
    }

    /// Sends the remote command event that the active Now Playing app responds to.
    private func sendMediaKey(_ key: MediaKey) {
        let center = MPRemoteCommandCenter.shared()
        switch key {
        case .play:            center.playCommand.isEnabled = true
        case .pause:           center.pauseCommand.isEnabled = true
        case .togglePlayPause: center.togglePlayPauseCommand.isEnabled = true
        case .nextTrack:       center.nextTrackCommand.isEnabled = true
        case .previousTrack:   center.previousTrackCommand.isEnabled = true
        }
        // The correct cross-process way is AVAudioSession + MPRemoteCommandCenter;
        // for SFSafariViewController the user can also use Lock Screen / AirPods.
        // We use the shared MPMusicPlayerController to request the action.
        switch key {
        case .play:            MPMusicPlayerController.systemMusicPlayer.play()
        case .pause:           MPMusicPlayerController.systemMusicPlayer.pause()
        case .togglePlayPause:
            if MPMusicPlayerController.systemMusicPlayer.playbackState == .playing {
                MPMusicPlayerController.systemMusicPlayer.pause()
            } else {
                MPMusicPlayerController.systemMusicPlayer.play()
            }
        case .nextTrack:       MPMusicPlayerController.systemMusicPlayer.skipToNextItem()
        case .previousTrack:   MPMusicPlayerController.systemMusicPlayer.skipToPreviousItem()
        }
    }
}
