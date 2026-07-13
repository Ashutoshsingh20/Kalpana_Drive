import AVFoundation
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
    @Published var destinationQuery = "" {
        didSet { searchCompleter.updateQuery(destinationQuery, coordinate: locationService.coordinate) }
    }
    @Published var isVoiceActive = false
    @Published var isDiagnosticsPresented = false

    // Map state
    @Published var mapStyle: DriveMapStyle = .standard
    @Published var followsHeading = true

    // Autocomplete
    @Published private(set) var searchSuggestions: [String] = []

    // Navigation progress (from NavigationEngine)
    @Published private(set) var navNextInstruction = ""
    @Published private(set) var navDistanceRemaining: Double = 0
    @Published private(set) var navETA: Date = Date()
    @Published private(set) var navProgressPercent: Double = 0
    @Published private(set) var navIsOffRoute = false
    @Published private(set) var navHasArrived = false
    @Published private(set) var navCurrentStreet = ""

    // Trip recording
    @Published private(set) var isTripRecording = false
    @Published private(set) var trips: [TripLog] = []

    // Parking
    @Published private(set) var parkedLocation: ParkedLocation?
    @Published private(set) var showsParkingPrompt = false
    @Published var parkingNote = ""
    @Published var parkingFloor = ""
    @Published var parkingSlot = ""

    // Saved places
    @Published private(set) var savedPlaces: [SavedPlace] = []
    @Published private(set) var recentDestinations: [Destination] = []

    // Route Intelligence
    @Published var avoidTolls = false
    @Published var avoidHighways = false
    @Published private(set) var roadPreferences: [PersonalRoadPreference] = []
    @Published var ignisFuelType: RouteIntelligenceService.IgnisFuelType = .petrol

    let iphoneBridge = iPhoneCompanionBridge()

    private var stateMachine = DrivingStateMachine()
    private let safetyPolicy = DrivingSafetyPolicy()
    private let locationService = LiveLocationService()
    private let mediaService = LiveMediaService()
    private let audioService = LiveAudioRouteService()
    private let connectivityService = ConnectivityService()
    private let navigationService = MapKitNavigationService()
    private let speechService = LiveSpeechService()
    private let contactService = NativeContactService()
    private let navigationEngine = NavigationEngine()
    private let tripRecorder = TripRecorder()
    private let parkingService = ParkingService()
    private let routeIntelligence = RouteIntelligenceService()
    private let savedPlacesService = SavedPlacesService()
    private let searchCompleter = SearchCompleterService()

    private var clockTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    var iphoneConnected: Bool { iphoneBridge.connectedPeer != nil }
    var iphoneMedia: PhoneBridgeMediaState { iphoneBridge.mediaState }
    var iphoneContacts: [PhoneBridgeContact] { iphoneBridge.contacts }

    // Native Contacts properties
    var nativeContacts: [KalpanaContact] { contactService.contacts }
    var contactsPermissionStatus: String {
        switch contactService.authorizationStatus {
        case .notDetermined: return "Not Determined"
        case .restricted: return "Restricted"
        case .denied: return "Denied"
        case .limited: return "Limited"
        case .authorized: return "Authorized"
        @unknown default: return "Unknown"
        }
    }

    var nativeFavourites: [KalpanaContact] {
        contactService.contacts.filter { $0.isFavourite }
    }

    var recentCalls: [KalpanaContact] {
        contactService.contacts
            .filter { $0.lastCalled != nil }
            .sorted { ($0.lastCalled ?? Date.distantPast) > ($1.lastCalled ?? Date.distantPast) }
    }

    var filteredContacts: [KalpanaContact] {
        let query = contactQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nativeContacts }
        return nativeContacts.filter { contact in
            contact.displayName.localizedCaseInsensitiveContains(query) ||
            contact.organisation.localizedCaseInsensitiveContains(query) ||
            contact.phoneNumbers.contains { num in
                num.number.localizedCaseInsensitiveContains(query) ||
                self.normalizeNumber(num.number).contains(self.normalizeNumber(query))
            }
        }
    }

    private func normalizeNumber(_ number: String) -> String {
        number.filter { $0.isNumber || $0 == "+" }
    }

    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        locationService.start()
        bindLiveServices()
        refreshLiveState()
        startClock()
        Task { await navigationService.restoreActiveRoute() }
        Task { await contactService.fetchContacts() }
        Task {
            if let stored = try? await JSONRouteRepository(
                fileURL: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                    .first!.appendingPathComponent("KalpanaDrive/active-route.json")
            ).loadActiveRoute(), stored.isActive {
                // Engine restores when the map section opens
            }
        }
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
        searchSuggestions = []
        Task {
            await navigationService.calculateRoute(to: result.destination)
            // Hand off to NavigationEngine for turn-by-turn once route is ready
            if let mkRoute = navigationService.mapRoute {
                navigationEngine.startNavigation(with: mkRoute, target: result.destination, alternatives: navigationService.alternativeRoutes)
                savedPlacesService.addRecentDestination(result.destination)
            }
        }
    }

    func startNavigation(to destination: Destination) {
        guard authorize(.openMap, source: .touch) else { return }
        destinationQuery = ""
        navigationService.clearSearch()
        searchSuggestions = []
        Task {
            await navigationService.calculateRoute(to: destination)
            if let mkRoute = navigationService.mapRoute {
                navigationEngine.startNavigation(with: mkRoute, target: destination, alternatives: navigationService.alternativeRoutes)
                savedPlacesService.addRecentDestination(destination)
            }
        }
    }

    func cancelNavigation() {
        guard authorize(.openMap, source: .touch) else { return }
        navigationService.cancelRoute()
        navigationEngine.cancelNavigation()
    }

    func selectAlternativeRoute(_ route: MKRoute) {
        navigationEngine.selectAlternativeRoute(route)
    }

    // MARK: — Trip Recording
    func startTripRecording() {
        guard let location = locationService.coordinate else {
            errorMessage = "GPS location is not available. Trip recording requires a valid location."
            return
        }
        let clLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
        tripRecorder.startTrip(location: clLocation)
        isTripRecording = true
    }

    func stopTripRecording() {
        tripRecorder.stopTrip()
        isTripRecording = false
        trips = tripRecorder.trips
    }

    func deleteTripLog(id: UUID) {
        tripRecorder.deleteTrip(id: id)
        trips = tripRecorder.trips
    }

    // MARK: — Parking
    func saveCurrentParking() {
        guard let location = locationService.coordinate else {
            errorMessage = "GPS location is not available. Cannot save parking location."
            return
        }
        parkingService.saveParking(
            coordinate: location,
            note: parkingNote,
            floor: parkingFloor,
            slot: parkingSlot
        )
        parkingNote = ""
        parkingFloor = ""
        parkingSlot = ""
    }

    func clearParking() {
        parkingService.clearParking()
    }

    func navigateToParking() {
        guard let parking = parkedLocation else { return }
        let dest = Destination(
            name: "My Parked Car",
            address: "Parking location",
            coordinate: parking.coordinate,
            kind: .recent
        )
        startNavigation(to: dest)
    }

    func dismissParkingPrompt() {
        showsParkingPrompt = false
    }

    func acceptParkingPrompt() {
        showsParkingPrompt = false
        if let coord = parkingService.suggestedCoordinate {
            parkingService.saveParking(
                coordinate: CLLocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude),
                note: "", floor: "", slot: ""
            )
        }
    }

    // MARK: — Saved Places
    func savePlace(name: String, address: String, coordinate: CLLocationCoordinate2D, label: SavedPlaceLabel, customName: String? = nil) {
        let place = SavedPlace(
            name: name,
            address: address,
            coordinate: Coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude),
            label: label,
            customLabelName: customName
        )
        savedPlacesService.savePlace(place)
    }

    func deleteSavedPlace(id: UUID) {
        savedPlacesService.deletePlace(id: id)
    }

    func clearRecentDestinations() {
        savedPlacesService.clearRecentDestinations()
    }

    // MARK: — Route Intelligence
    func setAvoidTolls(_ avoid: Bool) {
        avoidTolls = avoid
        routeIntelligence.setAvoidTolls(avoid)
    }

    func setAvoidHighways(_ avoid: Bool) {
        avoidHighways = avoid
        routeIntelligence.setAvoidHighways(avoid)
    }

    func avoidRoad(_ name: String) {
        routeIntelligence.avoidRoad(name)
        roadPreferences = routeIntelligence.roadPreferences
    }

    func preferRoad(_ name: String) {
        routeIntelligence.preferRoad(name)
        roadPreferences = routeIntelligence.roadPreferences
    }

    func deleteRoadPreference(_ name: String) {
        routeIntelligence.deleteRoadPreference(name)
        roadPreferences = routeIntelligence.roadPreferences
    }

    func setIgnisFuelType(_ type: RouteIntelligenceService.IgnisFuelType) {
        ignisFuelType = type
        routeIntelligence.ignisFuelType = type
    }

    func updateContactQuery(_ query: String) {
        contactQuery = query
    }

    func callPhoneNumber() {
        let number = phoneNumberToDial
        phoneNumberToDial = ""
        call(number: number)
    }

    func call(number: String, contactId: String? = nil) {
        let normalized = number.filter { $0.isNumber || $0 == "+" }
        guard !normalized.isEmpty,
              let url = URL(string: "tel:\(normalized)") else {
            errorMessage = "Invalid phone number."
            return
        }
        if UIApplication.shared.canOpenURL(url) {
            if let contactId {
                Task {
                    await contactService.recordCall(contactId: contactId)
                    objectWillChange.send()
                }
            }
            Task {
                let opened = await UIApplication.shared.open(url)
                if !opened {
                    errorMessage = "The system call interface could not be opened."
                }
            }
        } else {
            errorMessage = "Calling is not supported on this device configuration."
        }
    }

    func toggleFavourite(for contact: KalpanaContact) {
        Task {
            await contactService.toggleFavourite(contactId: contact.id)
            objectWillChange.send()
        }
    }

    func requestContactsPermission() {
        Task {
            await contactService.requestAccess()
            objectWillChange.send()
        }
    }

    func fetchNativeContacts() {
        Task {
            await contactService.fetchContacts()
            objectWillChange.send()
        }
    }

    func approveIPhoneConnection() {
        iphoneBridge.approvePendingConnection()
    }

    func rejectIPhoneConnection() {
        iphoneBridge.rejectPendingConnection()
    }

    func disconnectIPhone() {
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
            iphoneBridge.objectWillChange.eraseToAnyPublisher(),
            contactService.objectWillChange.eraseToAnyPublisher(),
            navigationEngine.objectWillChange.eraseToAnyPublisher(),
            tripRecorder.objectWillChange.eraseToAnyPublisher(),
            parkingService.objectWillChange.eraseToAnyPublisher(),
            savedPlacesService.objectWillChange.eraseToAnyPublisher(),
            searchCompleter.objectWillChange.eraseToAnyPublisher()
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
        let speed = max(0, locationService.speedMetresPerSecond)
        speedKPH = Int((speed * 3.6).rounded())
        media = mediaService.snapshot
        audioRoute = audioService.route
        activeRoute = navigationService.activeRoute
        mapRoute = navigationService.mapRoute
        alternativeRoutes = navigationService.alternativeRoutes
        searchResults = navigationService.searchResults
        isSearching = navigationService.isSearching
        isOnline = connectivityService.isOnline
        locationPermission = authorizationDescription(locationService.authorizationStatus)

        // NavigationEngine live state
        navNextInstruction = navigationEngine.nextInstruction
        navDistanceRemaining = navigationEngine.distanceRemainingMetres
        navETA = navigationEngine.expectedArrival
        navProgressPercent = navigationEngine.routeProgressPercentage
        navIsOffRoute = navigationEngine.isOffRoute
        navHasArrived = navigationEngine.hasArrived
        navCurrentStreet = navigationEngine.currentStreet

        // Feed live location to NavigationEngine
        if let coord = locationService.coordinate {
            let loc = CLLocation(
                coordinate: coord,
                altitude: 0,
                horizontalAccuracy: locationService.horizontalAccuracy ?? 10,
                verticalAccuracy: -1,
                course: locationService.courseDegrees ?? -1,
                speed: speed,
                timestamp: locationService.lastLocationTimestamp ?? Date()
            )
            navigationEngine.updateLocation(loc)
            parkingService.updateSpeedAndLocation(speedMPS: speed, coordinate: coord)
            if isTripRecording {
                tripRecorder.updateLocation(location: loc)
            }
        }

        // Trip / Parking state
        isTripRecording = tripRecorder.isRecording
        trips = tripRecorder.trips
        parkedLocation = parkingService.currentParking
        showsParkingPrompt = parkingService.showsSuggestionPrompt

        // Saved places
        savedPlaces = savedPlacesService.savedPlaces
        recentDestinations = savedPlacesService.recentDestinations

        // Autocomplete suggestions
        searchSuggestions = searchCompleter.suggestions.map { $0.title + ($0.subtitle.isEmpty ? "" : ", " + $0.subtitle) }

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
