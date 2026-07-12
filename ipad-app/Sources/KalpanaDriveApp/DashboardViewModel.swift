import Foundation
import KalpanaDriveCore

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var now = Date()
    @Published private(set) var drivingState: DrivingState = .phoneDisconnected
    @Published private(set) var speedKPH = 0
    @Published private(set) var media = MediaSnapshot(title: "Driving Mix", artist: "Kalpana Drive", isPlaying: false, elapsed: 42, duration: 214)
    @Published private(set) var phone = PhoneConnectionSnapshot(state: .disconnected, platform: .none, deviceName: nil, lastHeartbeat: nil)
    @Published private(set) var audioRoute: AudioRoute = .unknown
    @Published var appearance: DriveAppearance = .night
    @Published var controlHand: ControlHand = .left
    @Published var selectedSection: DashboardSection = .home
    @Published var voiceMessage = "Tap to speak"
    @Published var isVoiceActive = false
    @Published var isDiagnosticsPresented = false

    private let stateMachine = DrivingStateMachine()
    private let location: MockLocationProvider
    private let mediaService: MockMediaService
    private let phoneConnection: MockPhoneConnection
    private let audioManager: MockAudioRouteManager
    private let voiceRouter: LocalVoiceCommandRouter
    private var clockTask: Task<Void, Never>?
    private var simulatedMoving = false

    init(
        location: MockLocationProvider = MockLocationProvider(),
        mediaService: MockMediaService = MockMediaService(),
        phoneConnection: MockPhoneConnection = MockPhoneConnection(),
        audioManager: MockAudioRouteManager = MockAudioRouteManager(),
        voiceRouter: LocalVoiceCommandRouter = LocalVoiceCommandRouter()
    ) {
        self.location = location
        self.mediaService = mediaService
        self.phoneConnection = phoneConnection
        self.audioManager = audioManager
        self.voiceRouter = voiceRouter
        startClock()
        Task { await refresh() }
    }

    deinit { clockTask?.cancel() }

    func toggleSimulation() {
        simulatedMoving.toggle()
        Task {
            await location.setSpeed(simulatedMoving ? 13.9 : 0)
            await refresh()
        }
    }

    func togglePlayback() {
        Task {
            try? await mediaService.execute(media.isPlaying ? .pause : .play)
            media = await mediaService.currentState()
        }
    }

    func activateVoice() {
        guard !isVoiceActive else { return }
        isVoiceActive = true
        voiceMessage = "Listening simulation…"
        Task {
            try? await Task.sleep(for: .milliseconds(650))
            let response = await voiceRouter.route("what is my eta", state: drivingState)
            voiceMessage = response.visualText
            isVoiceActive = false
        }
    }

    func refresh() async {
        let speed = await location.currentSpeedMetresPerSecond()
        speedKPH = Int((speed * 3.6).rounded())
        media = await mediaService.currentState()
        phone = await phoneConnection.currentState()
        audioRoute = await audioManager.currentRoute()
        drivingState = stateMachine.resolve(
            DrivingContext(
                speedMetresPerSecond: speed,
                online: true,
                phoneConnected: phone.state == .connected
            )
        )
    }

    private func startClock() {
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.now = Date()
                try? await Task.sleep(for: .seconds(1))
            }
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

