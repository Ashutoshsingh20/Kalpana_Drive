import Combine
import CoreLocation
import Foundation
import KalpanaDriveCore
import Speech
import UIKit

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var now = Date()
    @Published private(set) var drivingState: DrivingState = .phoneDisconnected
    @Published private(set) var speedKPH = 0
    @Published private(set) var media: MediaSnapshot = .unavailable
    @Published private(set) var phone = PhoneConnectionSnapshot(
        state: .unavailable,
        platform: .none,
        deviceName: nil,
        lastHeartbeat: nil
    )
    @Published private(set) var audioRoute: AudioRoute = .unknown
    @Published private(set) var activeRoute: RouteSnapshot?
    @Published private(set) var isOnline = false
    @Published private(set) var locationPermission = "Checking"
    @Published private(set) var locationAccuracy = "No GPS fix"
    @Published private(set) var batteryStatus = "Checking"
    @Published private(set) var thermalStatus = "Nominal"
    @Published private(set) var errorMessage: String?

    @Published var appearance: DriveAppearance = .night
    @Published var controlHand: ControlHand = .left
    @Published var selectedSection: DashboardSection = .home
    @Published var voiceMessage = "Tap to speak"
    @Published var isVoiceActive = false
    @Published var isDiagnosticsPresented = false

    private var stateMachine = DrivingStateMachine()
    private let locationService = LiveLocationService()
    private let mediaService = LiveMediaService()
    private let phoneService = PhoneCompanionService()
    private let audioService = LiveAudioRouteService()
    private let connectivityService = ConnectivityService()
    private let navigationService = MapKitNavigationService()
    private let speechService = LiveSpeechService()

    private var refreshTask: Task<Void, Never>?

    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        locationService.start()
        startRefreshLoop()
    }

    deinit {
        refreshTask?.cancel()
    }

    func togglePlayback() {
        mediaService.execute(media.isPlaying ? .pause : .play)
        refreshLiveState()
    }

    func previousTrack() {
        mediaService.execute(.previous)
        refreshLiveState()
    }

    func nextTrack() {
        mediaService.execute(.next)
        refreshLiveState()
    }

    func activateVoice() {
        if speechService.isListening {
            speechService.stop()
            isVoiceActive = false
            voiceMessage = "Tap to speak"
            return
        }

        isVoiceActive = true
        voiceMessage = "Listening"
        speechService.start { [weak self] transcript in
            guard let self else { return }
            self.isVoiceActive = false
            self.handleVoiceTranscript(transcript)
        }

        if let error = speechService.lastError {
            isVoiceActive = false
            voiceMessage = error
            errorMessage = error
        }
    }

    func clearError() {
        errorMessage = nil
    }

    private func handleVoiceTranscript(_ transcript: String) {
        let command = transcript.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let response: String

        switch command {
        case "play music", "music chalao":
            mediaService.execute(.play)
            response = "Playing the current system music queue."
        case "pause music", "music pause karo":
            mediaService.execute(.pause)
            response = "Music paused."
        case "next song", "next track", "agla gana":
            mediaService.execute(.next)
            response = "Skipping to the next track."
        case "previous song", "previous track", "pichla gana":
            mediaService.execute(.previous)
            response = "Returning to the previous track."
        case "what is my eta", "eta kya hai":
            if let route = activeRoute {
                response = "Your estimated arrival is \(route.expectedArrival.formatted(date: .omitted, time: .shortened))."
            } else {
                response = "There is no active route."
            }
        case "navigate home", "take me home", "ghar chalo":
            response = "Home is not configured. Add a real home address before using this command."
        default:
            response = "That command is not supported yet."
        }

        voiceMessage = response
        speechService.speak(response)
        refreshLiveState()
    }

    private func startRefreshLoop() {
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refreshLiveState()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func refreshLiveState() {
        now = Date()
        speedKPH = Int((max(0, locationService.speedMetresPerSecond) * 3.6).rounded())
        media = mediaService.currentSnapshot()
        phone = phoneService.snapshot
        audioRoute = audioService.currentRoute()
        activeRoute = navigationService.activeRoute
        isOnline = connectivityService.isOnline
        locationPermission = authorizationDescription(locationService.authorizationStatus)

        if let accuracy = locationService.horizontalAccuracy {
            locationAccuracy = "±\(Int(accuracy.rounded())) m"
        } else {
            locationAccuracy = "No GPS fix"
        }

        let batteryLevel = UIDevice.current.batteryLevel
        if batteryLevel >= 0 {
            let percentage = Int((batteryLevel * 100).rounded())
            batteryStatus = "\(percentage)% • \(batteryStateDescription(UIDevice.current.batteryState))"
        } else {
            batteryStatus = "Unavailable"
        }

        thermalStatus = thermalDescription(ProcessInfo.processInfo.thermalState)

        errorMessage = locationService.lastError ?? speechService.lastError ?? navigationService.lastError

        drivingState = stateMachine.update(
            DrivingContext(
                speedMetresPerSecond: locationService.speedMetresPerSecond,
                lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
                thermalLimited: ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical,
                online: isOnline,
                phoneConnected: phone.state == .connected,
                locationAvailable: locationService.hasFreshLocation
            )
        )
    }

    private func authorizationDescription(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: "Not requested"
        case .restricted: "Restricted"
        case .denied: "Denied"
        case .authorizedAlways: "Always"
        case .authorizedWhenInUse: "While using app"
        @unknown default: "Unknown"
        }
    }

    private func batteryStateDescription(_ state: UIDevice.BatteryState) -> String {
        switch state {
        case .unknown: "Unknown"
        case .unplugged: "On battery"
        case .charging: "Charging"
        case .full: "Fully charged"
        @unknown default: "Unknown"
        }
    }

    private func thermalDescription(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "Nominal"
        case .fair: "Warm"
        case .serious: "Hot — reduced interaction"
        case .critical: "Critical — stop using and cool the iPad"
        @unknown default: "Unknown"
        }
    }
}

enum DashboardSection: String, CaseIterable, Identifiable {
    case home = "Home"
    case map = "Map"
    case music = "Music"
    case phone = "Phone"
    case settings = "Settings"

    var id: Self { self }
}
