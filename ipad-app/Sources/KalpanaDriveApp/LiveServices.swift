import AVFoundation
import Combine
import CoreLocation
import Foundation
import KalpanaDriveCore
import MapKit
import MediaPlayer
import Network
import Speech

@MainActor
final class LiveLocationService: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published private(set) var coordinate: CLLocationCoordinate2D?
    @Published private(set) var speedMetresPerSecond: Double = 0
    @Published private(set) var horizontalAccuracy: CLLocationAccuracy?
    @Published private(set) var courseDegrees: CLLocationDirection?
    @Published private(set) var headingDegrees: CLLocationDirection?
    @Published private(set) var lastLocationTimestamp: Date?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var lastError: String?

    private let manager = CLLocationManager()

    var hasFreshLocation: Bool {
        guard let lastLocationTimestamp else { return false }
        return Date().timeIntervalSince(lastLocationTimestamp) <= 15
    }

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.activityType = .automotiveNavigation
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 3
        manager.pausesLocationUpdatesAutomatically = false
    }

    func start() {
        authorizationStatus = manager.authorizationStatus
        switch authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
            manager.startUpdatingHeading()
        case .denied, .restricted:
            lastError = "Location access is disabled. Enable it in Settings to use GPS and the live map."
        @unknown default:
            lastError = "The current location authorization state is not supported."
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
            lastError = nil
            manager.startUpdatingLocation()
            manager.startUpdatingHeading()
        } else if authorizationStatus == .denied || authorizationStatus == .restricted {
            lastError = "Location access is disabled. Enable it in Settings to use GPS and the live map."
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last,
              abs(location.timestamp.timeIntervalSinceNow) <= 15,
              location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= 50 else { return }

        coordinate = location.coordinate
        horizontalAccuracy = location.horizontalAccuracy
        speedMetresPerSecond = location.speed >= 0 ? location.speed : 0
        courseDegrees = location.course >= 0 ? location.course : nil
        lastLocationTimestamp = location.timestamp
        lastError = nil
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }
        headingDegrees = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        lastError = error.localizedDescription
    }
}

@MainActor
final class LiveMediaService: ObservableObject {
    @Published private(set) var snapshot: MediaSnapshot = .unavailable
    private let player = MPMusicPlayerController.systemMusicPlayer
    private var cancellables = Set<AnyCancellable>()

    init() {
        player.beginGeneratingPlaybackNotifications()
        let center = NotificationCenter.default
        Publishers.Merge3(
            center.publisher(for: .MPMusicPlayerControllerNowPlayingItemDidChange),
            center.publisher(for: .MPMusicPlayerControllerPlaybackStateDidChange),
            center.publisher(for: .MPMusicPlayerControllerVolumeDidChange)
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in self?.refresh() }
        .store(in: &cancellables)
        refresh()
    }

    private func refresh() {
        guard let item = player.nowPlayingItem else {
            snapshot = .unavailable
            return
        }
        snapshot = MediaSnapshot(
            title: item.title ?? "Untitled track",
            artist: item.artist ?? "Unknown artist",
            isPlaying: player.playbackState == .playing,
            elapsed: max(0, player.currentPlaybackTime),
            duration: max(0, item.playbackDuration)
        )
    }

    func execute(_ command: MediaCommand) {
        switch command {
        case .play:
            player.play()
        case .pause:
            player.pause()
        case .previous:
            player.skipToPreviousItem()
        case .next:
            player.skipToNextItem()
        }
        refresh()
    }
}

@MainActor
final class LiveAudioRouteService: ObservableObject {
    @Published private(set) var route: AudioRoute = .unknown
    @Published private(set) var routeName = "Unknown"
    private var cancellable: AnyCancellable?

    init() {
        refresh()
        cancellable = NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
    }

    private func refresh() {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        routeName = outputs.map(\.portName).filter { !$0.isEmpty }.joined(separator: ", ")
        if outputs.contains(where: { output in
            output.portType == .bluetoothA2DP ||
            output.portType == .bluetoothHFP ||
            output.portType == .bluetoothLE ||
            output.portType == .carAudio
        }) {
            route = .bluetooth
            return
        }
        if outputs.contains(where: { $0.portType == .builtInSpeaker }) {
            route = .ipadSpeaker
            return
        }
        route = .unknown
    }
}

@MainActor
final class ConnectivityService: ObservableObject {
    @Published private(set) var isOnline = false
    @Published private(set) var usesCellular = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.kalpana.drive.network-monitor")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOnline = path.status == .satisfied
                self?.usesCellular = path.usesInterfaceType(.cellular)
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}



@MainActor
final class MapKitNavigationService: ObservableObject {
    @Published private(set) var activeRoute: RouteSnapshot?
    @Published private(set) var mapRoute: MKRoute?
    @Published private(set) var alternativeRoutes: [MKRoute] = []
    @Published private(set) var searchResults: [MapSearchResult] = []
    @Published private(set) var isSearching = false
    @Published private(set) var lastError: String?

    private let routeRepository: any RouteRepository

    init(routeRepository: (any RouteRepository)? = nil) {
        self.routeRepository = routeRepository ?? JSONRouteRepository(fileURL: Self.defaultRouteURL)
    }

    func search(_ query: String, near coordinate: CLLocationCoordinate2D?) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            searchResults = []
            lastError = "Enter at least two characters to search."
            return
        }

        isSearching = true
        defer { isSearching = false }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.resultTypes = [.address, .pointOfInterest]
        if let coordinate {
            request.region = MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: 50_000,
                longitudinalMeters: 50_000
            )
        }

        do {
            let response = try await MKLocalSearch(request: request).start()
            searchResults = response.mapItems.prefix(8).map(MapSearchResult.init)
            lastError = searchResults.isEmpty ? "No places matched that search." : nil
        } catch {
            searchResults = []
            lastError = "Place search failed: \(error.localizedDescription)"
        }
    }

    func clearSearch() {
        searchResults = []
    }

    func calculateRoute(to destination: Destination) async {
        let request = MKDirections.Request()
        request.source = .forCurrentLocation()
        request.destination = MKMapItem(
            placemark: MKPlacemark(
                coordinate: CLLocationCoordinate2D(
                    latitude: destination.coordinate.latitude,
                    longitude: destination.coordinate.longitude
                )
            )
        )
        request.transportType = .automobile
        request.requestsAlternateRoutes = true

        do {
            let response = try await MKDirections(request: request).calculate()
            guard let route = response.routes.min(by: { $0.expectedTravelTime < $1.expectedTravelTime }) else {
                throw NavigationServiceError.noRoute
            }
            mapRoute = route
            alternativeRoutes = response.routes.filter { $0 !== route }
            activeRoute = RouteSnapshot(
                destination: destination,
                nextInstruction: route.steps.first(where: { !$0.instructions.isEmpty })?.instructions ?? "Route ready",
                distanceRemainingMetres: route.distance,
                expectedArrival: Date().addingTimeInterval(route.expectedTravelTime),
                isActive: true
            )
            if let activeRoute {
                try await routeRepository.save(activeRoute)
            }
            lastError = nil
        } catch {
            mapRoute = nil
            alternativeRoutes = []
            activeRoute = nil
            lastError = "Route calculation failed: \(error.localizedDescription)"
        }
    }

    func restoreActiveRoute() async {
        do {
            guard let stored = try await routeRepository.loadActiveRoute() else { return }
            await calculateRoute(to: stored.destination)
        } catch {
            lastError = "Saved route could not be restored: \(error.localizedDescription)"
        }
    }

    func cancelRoute() {
        mapRoute = nil
        alternativeRoutes = []
        activeRoute = nil
        lastError = nil
        Task {
            do { try await routeRepository.clear() }
            catch { lastError = "The saved route could not be cleared: \(error.localizedDescription)" }
        }
    }

    enum NavigationServiceError: LocalizedError {
        case noRoute

        var errorDescription: String? {
            "MapKit could not calculate a driving route to this destination."
        }
    }

    private static var defaultRouteURL: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return root.appendingPathComponent("KalpanaDrive/active-route.json")
    }
}

struct MapSearchResult: Identifiable {
    let id = UUID()
    let mapItem: MKMapItem
    let name: String
    let address: String

    init(mapItem: MKMapItem) {
        self.mapItem = mapItem
        name = mapItem.name ?? "Unnamed place"
        address = mapItem.placemark.title ?? "Address unavailable"
    }

    var destination: Destination {
        let coordinate = mapItem.placemark.coordinate
        return Destination(
            name: name,
            address: address,
            coordinate: Coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude),
            kind: .recent
        )
    }
}

@MainActor
final class LiveSpeechService: NSObject, ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var authorizationStatus = SFSpeechRecognizer.authorizationStatus()
    @Published private(set) var lastError: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-IN"))
    private let audioEngine = AVAudioEngine()
    private let synthesizer = AVSpeechSynthesizer()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    func start(onTranscript: @escaping @MainActor (String) -> Void) {
        guard !isListening else {
            stop()
            return
        }

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                self.authorizationStatus = status
                guard status == .authorized else {
                    self.lastError = "Speech recognition permission is required for voice control."
                    return
                }
                self.beginRecognition(onTranscript: onTranscript)
            }
        }
    }

    func stop() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-IN")
        utterance.rate = 0.48
        synthesizer.speak(utterance)
    }

    private func beginRecognition(onTranscript: @escaping @MainActor (String) -> Void) {
        stop()
        lastError = nil

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers, .allowBluetoothHFP])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            recognitionRequest = request

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw SpeechServiceError.microphoneUnavailable
            }

            input.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
                request.append(buffer)
            }
            audioEngine.prepare()
            try audioEngine.start()
            isListening = true

            recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result {
                        let transcript = result.bestTranscription.formattedString
                        if result.isFinal {
                            self.stop()
                            onTranscript(transcript)
                        }
                    }
                    if let error {
                        self.lastError = error.localizedDescription
                        self.stop()
                    }
                }
            }
        } catch {
            lastError = error.localizedDescription
            stop()
        }
    }

    enum SpeechServiceError: LocalizedError {
        case microphoneUnavailable

        var errorDescription: String? {
            "No usable microphone input is available."
        }
    }
}
