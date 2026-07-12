import Combine
import CoreLocation
import Foundation
import KalpanaDriveCore
import MapKit
import Speech
import UIKit

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var now = Date()
    @Published private(set) var drivingState: DrivingState = .parked
    @Published private(set) var speedKPH = 0
    @Published private(set) var media: MediaSnapshot = .unavailable
    @Published var phoneNumberToDial = ""
    @Published var contactQuery = ""
    @Published private(set) var audioRoute: AudioRoute = .unknown
    @Published private(set) var activeRoute: RouteSnapshot?
    @Published private(set) var mapRoute: MKRoute?
    @Published private(set) var alternativeRoutes: [MKRoute] = []
    @Published private(set) var searchResults: [MapSearchResult] = []
    @Published private(set) var isSearching = false
    @Published private(set) var isOnline = false
    @Published private(set) var locationPermission = "Checking"
    @Published private(set) var locationAccuracy = "No GPS fix"
    @Published private(set) var batteryStatus = "Checking"
    @Published private(set) var thermalStatus = "Nominal"
    @Published private(set) var errorMessage: String?

    @Published private(set) var appearance: DriveAppearance = .night
    @Published var controlHand: ControlHand = .left
    @Published private(set) var selectedSection: DashboardSection = .home
    @Published var voiceMessage = "Tap to speak"
    @Published var destinationQuery = ""
    @Published var isVoiceActive = false
    @Published var isDiagnosticsPresented = false

    let iphoneBridge = iPhoneCompanionBridge()

    private var stateMachine = DrivingStateMachine()
    private let safetyPolicy = DrivingSafetyPolicy()
    private let locationService = LiveLocationService()
    private let mediaService = LiveMediaService()
    private let audioService = LiveAudioRouteService()
    private let connectivityService = ConnectivityService()
    private let navigationService = MapKitNavigationService()
    private let speechService = LiveSpeechService()

    private var clockTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    var iphoneConnected: Bool { iphoneBridge.connectedPeer != nil }
    var iphoneMedia: PhoneBridgeMediaState { iphoneBridge.mediaState }
    var iphoneContacts: [PhoneBridgeContact] { iphoneBridge.contacts }

    var filteredIPhoneContacts: [PhoneBridgeContact] {
        let query = contactQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return Array(iphoneBridge.contacts.prefix(50)) }
        return iphoneBridge.contacts.filter {
            $0.displayName.localizedCaseInsensitiveContains(query) ||
            $0.phoneNumbers.contains(where: { $0.localizedCaseInsensitiveContains(query) })
        }
        .prefix(50)
        .map { $0 }
    }

    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        locationService.start()
        bindLiveServices()
        refreshLiveState()
        startClock()
        Task { await navigationService.restoreActiveRoute() }
    }

    deinit {
        clockTask?.cancel()
    }

    func togglePlayback() {
        guard authorize(.controlMedia, source: .touch) else { return }
        mediaService.execute(media.isPlaying ? .pause : .play)
        refreshLiveState()
    }

    func previousTrack() {
        guard authorize(.controlMedia, source: .touch) else { return }
        mediaService.execute(.previous)
        refreshLiveState()
    }

    func nextTrack() {
        guard authorize(.controlMedia, source: .touch) else { return }
        mediaService.execute(.next)
        refreshLiveState()
    }

    func toggleIPhonePlayback() {
        guard authorize(.controlMedia, source: .touch), iphoneConnected else { return }
        iphoneBridge.sendMediaCommand(iphoneMedia.isPlaying ? .pause : .play)
    }

    func previousIPhoneTrack() {
        guard authorize(.controlMedia, source: .touch), iphoneConnected else { return }
        iphoneBridge.sendMediaCommand(.previous)
    }

    func nextIPhoneTrack() {
        guard authorize(.controlMedia, source: .touch), iphoneConnected else { return }
        iphoneBridge.sendMediaCommand(.next)
    }

    func openYouTubeMusic() {
        guard authorize(.openExternalMedia, source: .touch),
              let url = URL(string: "https://music.youtube.com") else { return }
        Task {
            let opened = await UIApplication.shared.open(url)
            if !opened {
                errorMessage = "YouTube Music could not be opened. Install it or check network access."
            }
        }
    }

    func activateVoice() {
        guard authorize(.useVoice, source: .touch) else { return }
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

    func selectSection(_ section: DashboardSection, source: ActionSource = .touch) {
        let action: DrivingAction = switch section {
        case .home: .openDashboard
        case .map: .openMap
        case .music: .openMusic
        case .phone: .openPhone
        case .settings: .openSettings
        }
        guard authorize(action, source: source) else { return }
        selectedSection = section
    }

    func openDiagnostics() {
        guard authorize(.openSettings, source: .touch) else { return }
        isDiagnosticsPresented = true
    }

    func setAppearance(_ newAppearance: DriveAppearance) {
        guard authorize(.openSettings, source: .touch) else { return }
        appearance = newAppearance
    }

    func searchDestinations() {
        guard authorize(.typeDestination, source: .touch) else { return }
        let query = destinationQuery
        Task { await navigationService.search(query, near: locationService.coordinate) }
    }

    func startNavigation(to result: MapSearchResult) {
        guard authorize(.openMap, source: .touch) else { return }
        destinationQuery = ""
        navigationService.clearSearch()
        Task { await navigationService.calculateRoute(to: result.destination) }
    }

    func cancelNavigation() {
        guard authorize(.openMap, source: .touch) else { return }
        navigationService.cancelRoute()
    }

    func updateContactQuery(_ query: String) {
        guard authorize(.browseContacts, source: .touch) else {
            contactQuery = ""
            return
        }
        contactQuery = query
    }

    func callPhoneNumber() {
        guard authorize(.typePhoneNumber, source: .touch) else { return }
        let number = phoneNumberToDial
        phoneNumberToDial = ""
        call(number: number)
    }

    func call(number: String) {
        guard authorize(.placeCall, source: .touch) else { return }
        let normalized = number.filter { $0.isNumber || $0 == "+" }
        guard !normalized.isEmpty,
              let url = URL(string: "tel://\(normalized)"),
              UIApplication.shared.canOpenURL(url) else {
            errorMessage = "Calling is not available on this iPad. Enable Calls from iPhone/Continuity or use a cellular-capable calling configuration."
            return
        }
        Task {
            let opened = await UIApplication.shared.open(url)
            if !opened {
                errorMessage = "The system call interface could not be opened."
            }
        }
    }

    func approveIPhoneConnection() {
        guard authorize(.manageDevices, source: .touch) else { return }
        iphoneBridge.approvePendingConnection()
    }

    func rejectIPhoneConnection() {
        guard authorize(.manageDevices, source: .touch) else { return }
        iphoneBridge.rejectPendingConnection()
    }

    func disconnectIPhone() {
        guard authorize(.manageDevices, source: .touch) else { return }
        iphoneBridge.disconnect()
    }

    func syncIPhone() {
        guard iphoneConnected else {
            errorMessage = "No iPhone companion is connected."
            return
        }
        iphoneBridge.requestFullSync()
    }

    @discardableResult
    private func authorize(_ action: DrivingAction, source: ActionSource) -> Bool {
        let decision = safetyPolicy.evaluate(action, state: drivingState, source: source)
        if let reason = decision.reason { errorMessage = reason }
        return decision.isAllowed
    }

    private func handleVoiceTranscript(_ transcript: String) {
        let command = transcript.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let response: String

        switch command {
        case "play music", "music chalao":
            guard authorize(.controlMedia, source: .voice) else { return }
            if iphoneConnected {
                iphoneBridge.sendMediaCommand(.play)
                response = "Playing Apple Music on the connected iPhone."
            } else {
                mediaService.execute(.play)
                response = "Playing the current iPad Apple Music queue."
            }
        case "pause music", "music pause karo":
            guard authorize(.controlMedia, source: .voice) else { return }
            if iphoneConnected {
                iphoneBridge.sendMediaCommand(.pause)
                response = "Pausing Apple Music on the connected iPhone."
            } else {
                mediaService.execute(.pause)
                response = "Music paused on the iPad."
            }
        case "next song", "next track", "agla gana":
            guard authorize(.controlMedia, source: .voice) else { return }
            if iphoneConnected {
                iphoneBridge.sendMediaCommand(.next)
                response = "Skipping the iPhone Apple Music track."
            } else {
                mediaService.execute(.next)
                response = "Skipping the iPad Apple Music track."
            }
        case "previous song", "previous track", "pichla gana":
            guard authorize(.controlMedia, source: .voice) else { return }
            if iphoneConnected {
                iphoneBridge.sendMediaCommand(.previous)
                response = "Returning to the previous iPhone Apple Music track."
            } else {
                mediaService.execute(.previous)
                response = "Returning to the previous iPad Apple Music track."
            }
        case "what is my eta", "eta kya hai":
            if let route = activeRoute {
                response = "Your estimated arrival is \(route.expectedArrival.formatted(date: .omitted, time: .shortened))."
            } else {
                response = "There is no active route."
            }
        case "navigate home", "take me home", "ghar chalo":
            response = "Home is not configured. Add a real home address before using this command."
        default:
            if command.hasPrefix("call ") {
                let name = String(command.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
                let matches = iphoneBridge.contacts.filter { $0.displayName.localizedCaseInsensitiveContains(name) }
                if let contact = matches.first, let number = contact.phoneNumbers.first {
                    call(number: number)
                    response = "Opening the system call interface for \(contact.displayName)."
                } else {
                    response = "I could not find that person in the contacts shared by your iPhone."
                }
            } else {
                response = "That command is not supported yet."
            }
        }

        voiceMessage = response
        speechService.speak(response)
        refreshLiveState()
    }

    private func bindLiveServices() {
        Publishers.MergeMany([
            locationService.objectWillChange.eraseToAnyPublisher(),
            mediaService.objectWillChange.eraseToAnyPublisher(),
            audioService.objectWillChange.eraseToAnyPublisher(),
            connectivityService.objectWillChange.eraseToAnyPublisher(),
            navigationService.objectWillChange.eraseToAnyPublisher(),
            speechService.objectWillChange.eraseToAnyPublisher(),
            iphoneBridge.objectWillChange.eraseToAnyPublisher()
        ])
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            DispatchQueue.main.async { self?.refreshLiveState() }
        }
        .store(in: &cancellables)

        let center = NotificationCenter.default
        Publishers.MergeMany([
            center.publisher(for: UIDevice.batteryLevelDidChangeNotification).map { _ in }.eraseToAnyPublisher(),
            center.publisher(for: UIDevice.batteryStateDidChangeNotification).map { _ in }.eraseToAnyPublisher(),
            center.publisher(for: .NSProcessInfoPowerStateDidChange).map { _ in }.eraseToAnyPublisher(),
            center.publisher(for: ProcessInfo.thermalStateDidChangeNotification).map { _ in }.eraseToAnyPublisher()
        ])
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in self?.refreshLiveState() }
        .store(in: &cancellables)
    }

    private func startClock() {
        clockTask = Task { [weak self] in
            var secondsUntilFreshnessCheck = 5
            while !Task.isCancelled {
                self?.now = Date()
                try? await Task.sleep(for: .seconds(1))
                secondsUntilFreshnessCheck -= 1
                if secondsUntilFreshnessCheck == 0 {
                    self?.refreshLiveState()
                    secondsUntilFreshnessCheck = 5
                }
            }
        }
    }

    private func refreshLiveState() {
        now = Date()
        speedKPH = Int((max(0, locationService.speedMetresPerSecond) * 3.6).rounded())
        media = mediaService.snapshot
        audioRoute = audioService.route
        activeRoute = navigationService.activeRoute
        mapRoute = navigationService.mapRoute
        alternativeRoutes = navigationService.alternativeRoutes
        searchResults = navigationService.searchResults
        isSearching = navigationService.isSearching
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

        errorMessage = locationService.lastError ?? speechService.lastError ?? navigationService.lastError ?? iphoneBridge.lastError

        drivingState = stateMachine.update(
            DrivingContext(
                speedMetresPerSecond: locationService.speedMetresPerSecond,
                lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
                thermalLimited: ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical,
                online: isOnline,
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
