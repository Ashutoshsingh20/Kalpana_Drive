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
final class LiveLocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var coordinate: CLLocationCoordinate2D?
    @Published private(set) var speedMetresPerSecond: Double = 0
    @Published private(set) var horizontalAccuracy: CLLocationAccuracy?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var lastError: String?

    private let manager = CLLocationManager()

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
              location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= 100 else { return }

        coordinate = location.coordinate
        horizontalAccuracy = location.horizontalAccuracy
        speedMetresPerSecond = location.speed >= 0 ? location.speed : 0
        lastError = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        lastError = error.localizedDescription
    }
}

@MainActor
final class LiveMediaService {
    private let player = MPMusicPlayerController.systemMusicPlayer

    func currentSnapshot() -> MediaSnapshot {
        guard let item = player.nowPlayingItem else { return .unavailable }
        return MediaSnapshot(
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
    }
}

@MainActor
final class LiveAudioRouteService {
    func currentRoute() -> AudioRoute {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        if outputs.contains(where: { output in
            output.portType == .bluetoothA2DP ||
            output.portType == .bluetoothHFP ||
            output.portType == .bluetoothLE ||
            output.portType == .carAudio
        }) {
            return .bluetooth
        }
        if outputs.contains(where: { $0.portType == .builtInSpeaker }) {
            return .ipadSpeaker
        }
        return .unknown
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
final class PhoneCompanionService: ObservableObject {
    @Published private(set) var snapshot = PhoneConnectionSnapshot(
        state: .unavailable,
        platform: .none,
        deviceName: nil,
        lastHeartbeat: nil
    )

    var statusMessage: String {
        "No iPhone or Android companion is installed and paired."
    }
}

@MainActor
final class MapKitNavigationService: ObservableObject {
    @Published private(set) var activeRoute: RouteSnapshot?
    @Published private(set) var mapRoute: MKRoute?
    @Published private(set) var lastError: String?

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
            activeRoute = RouteSnapshot(
                destination: destination,
                nextInstruction: route.steps.first(where: { !$0.instructions.isEmpty })?.instructions ?? "Route ready",
                distanceRemainingMetres: route.distance,
                expectedArrival: Date().addingTimeInterval(route.expectedTravelTime),
                isActive: true
            )
            lastError = nil
        } catch {
            mapRoute = nil
            activeRoute = nil
            lastError = error.localizedDescription
        }
    }

    func cancelRoute() {
        mapRoute = nil
        activeRoute = nil
        lastError = nil
    }

    enum NavigationServiceError: LocalizedError {
        case noRoute

        var errorDescription: String? {
            "MapKit could not calculate a driving route to this destination."
        }
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
