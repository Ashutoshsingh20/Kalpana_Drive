import Combine
import KalpanaDriveCore
import MapKit
import SwiftUI
import UIKit

struct DashboardView: View {
    @ObservedObject var model: DashboardViewModel
    @State private var showSiriHelp = false
    @State private var showAskDrive = false

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                // Left vertical sidebar
                LeftSidebar(model: model, showSiriHelp: $showSiriHelp)
                
                // Main content area
                VStack(spacing: 16) {
                    if let error = model.errorMessage {
                        ErrorBanner(message: error, dismiss: model.clearError)
                            .padding(.horizontal, 16)
                    }
                    
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                    
                    BottomNavigationBar(model: model)
                        .padding(.bottom, 16)
                }
                .background(Color(white: 0.03)) // Deep dark background
            }
            
            // Voice Assistant Overlay (floating when active on other tabs)
            if model.voiceAssistant.state != .idle && model.selectedSection != .map {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        VoiceAssistantOverlay(coordinator: model.voiceAssistant, onKeyboardTap: {
                            model.voiceAssistant.cancelListening()
                            showAskDrive = true
                        })
                        .padding(24)
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark) // Locked to dark theme for premium feel
        .sheet(isPresented: $model.isDiagnosticsPresented) {
            DiagnosticsView(model: model)
        }
        .sheet(isPresented: $showAskDrive) {
            AskDriveView(model: model)
        }
        .alert("Use Siri with Kalpana Drive", isPresented: $showSiriHelp) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Say “Siri” or hold the iPad’s top button. Try “Open YouTube Music in Kalpana Drive”, “Open the map in Kalpana Drive”, or “Search for India Gate in Kalpana Drive”. Siri appears over this app instead of replacing the dashboard.")
        }
        .onAppear(perform: consumeSiriCommand)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            consumeSiriCommand()
        }
    }

    @ViewBuilder
    private var content: some View {
        ZStack {
            HomeSection(model: model)
                .sectionVisibility(isVisible: model.selectedSection == .home)
            NavigationMapSection(model: model)
                .sectionVisibility(isVisible: model.selectedSection == .map)
            MusicSection(model: model)
                .sectionVisibility(isVisible: model.selectedSection == .music)
            PhoneSection(model: model)
                .sectionVisibility(isVisible: model.selectedSection == .phone)
            SettingsSection(model: model)
                .sectionVisibility(isVisible: model.selectedSection == .settings)
        }
    }

    private func consumeSiriCommand() {
        guard let command = SiriDriveCommandStore.consume() else { return }
        switch command.kind {
        case .openDashboard:
            model.selectSection(.home, source: .system)
        case .openMap:
            model.selectSection(.map, source: .system)
        case .openMusic:
            model.selectSection(.music, source: .system)
        case .searchDestination:
            model.selectSection(.map, source: .system)
            model.destinationQuery = command.value ?? ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                model.searchDestinations()
            }
        }
    }

    private var palette: DrivePalette {
        DrivePalette(appearance: model.appearance)
    }
}

private struct StatusBar: View {
    @ObservedObject var model: DashboardViewModel
    let palette: DrivePalette

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.now, format: .dateTime.hour().minute())
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                Text(model.now, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.headline)
            }
            Spacer()
            HStack(spacing: 6) {
                StatusPill(text: model.drivingState.rawValue, prominent: model.drivingState.restrictsInteraction, palette: palette)
                StatusPill(text: "GPS: \(model.locationAccuracy)", palette: palette)
                StatusPill(text: "AUDIO: \(model.audioRoute.rawValue.uppercased())", palette: palette)
                StatusPill(text: model.isOnline ? "ONLINE" : "OFFLINE", prominent: !model.isOnline, palette: palette)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct StatusPill: View {
    let text: String
    var prominent = false
    let palette: DrivePalette

    var body: some View {
        if prominent {
            Text(text)
                .font(.caption.bold())
                .padding(.horizontal, 12)
                .frame(minHeight: 42)
                .background(palette.foreground)
                .foregroundStyle(palette.background)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Text(text)
                .font(.caption.bold())
                .padding(.horizontal, 12)
                .frame(minHeight: 42)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(palette.foreground)
        }
    }
}

private struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.headline).lineLimit(2)
            Spacer()
            Button("Dismiss", action: dismiss).buttonStyle(.bordered)
        }
        .padding(14)
        .glassEffect(.regular.tint(.orange.opacity(0.15)), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct LeftSidebar: View {
    @ObservedObject var model: DashboardViewModel
    @Binding var showSiriHelp: Bool

    var body: some View {
        VStack(spacing: 24) {
            // Logo
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    .frame(width: 44, height: 44)
                Text("K")
                    .font(.system(size: 20, weight: .light, design: .serif))
                    .foregroundStyle(.white)
            }
            .padding(.top, 16)

            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(height: 1)
                .padding(.horizontal, 16)

            // Navigation Icons
            VStack(spacing: 28) {
                ForEach(DashboardSection.allCases) { section in
                    let isSelected = model.selectedSection == section
                    Button {
                        model.selectSection(section)
                    } label: {
                        Image(systemName: icon(for: section))
                            .font(.system(size: 20))
                            .foregroundStyle(isSelected ? .white : .white.opacity(0.4))
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(isSelected ? Color.white.opacity(0.1) : Color.clear)
                            )
                            .overlay(
                                Circle()
                                    .stroke(isSelected ? Color.white.opacity(0.5) : Color.clear, lineWidth: 1)
                                    .shadow(color: isSelected ? .white.opacity(0.5) : .clear, radius: 4)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(height: 1)
                .padding(.horizontal, 16)

            // Power button (Toggles theme as an interactive mockup action)
            Button {
                if model.appearance == .night {
                    model.setAppearance(.day)
                } else {
                    model.setAppearance(.night)
                }
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 22))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 16)
        }
        .frame(width: 80)
        .background(Color(white: 0.05))
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1),
            alignment: .trailing
        )
    }

    private func icon(for section: DashboardSection) -> String {
        switch section {
        case .home: return "house"
        case .map: return "location.north.fill"
        case .music: return "music.note"
        case .phone: return "phone"
        case .settings: return "gearshape"
        }
    }
}

struct BottomNavigationBar: View {
    @ObservedObject var model: DashboardViewModel

    var body: some View {
        HStack(spacing: 12) {
            bottomBarButton(for: .home, title: "Home", systemImage: "sofa.fill")
            bottomBarButton(for: .map, title: "Map", systemImage: "location.fill")
            bottomBarButton(for: .music, title: "Music", systemImage: "music.note")
            bottomBarButton(for: .phone, title: "Phone", systemImage: "phone.fill")
            bottomBarButton(for: .settings, title: "More", systemImage: "circle.grid.2x2.fill")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func bottomBarButton(for section: DashboardSection, title: String, systemImage: String) -> some View {
        let isSelected = model.selectedSection == section
        Button {
            model.selectSection(section)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 16))
                Text(title)
                    .font(.system(size: 14, weight: .medium))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .foregroundStyle(isSelected ? .white : .white.opacity(0.6))
            .background(
                Capsule()
                    .fill(isSelected ? Color.white.opacity(0.12) : Color.clear)
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.white.opacity(0.8) : Color.white.opacity(0.2), lineWidth: 1)
                    .shadow(color: isSelected ? .white.opacity(0.5) : .clear, radius: 4)
            )
        }
        .buttonStyle(.plain)
    }
}

struct TurnByTurnOverlay: View {
    let nextInstruction: String
    let distanceRemaining: Double
    let currentStreet: String

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.3))
                Image(systemName: "arrow.turn.up.right")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(distanceString)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("m")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Text(instructionString)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text(streetString)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.85))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var distanceString: String {
        if distanceRemaining > 0 {
            if distanceRemaining >= 1000 {
                return String(format: "%.1f km", distanceRemaining / 1000)
            } else {
                return "\(Int(distanceRemaining))"
            }
        }
        return "300"
    }

    private var instructionString: String {
        if !nextInstruction.isEmpty {
            return nextInstruction
        }
        return "Turn right"
    }

    private var streetString: String {
        if !currentStreet.isEmpty {
            return currentStreet
        }
        return "Noida-Greater Noida Expressway"
    }
}

struct SpeedometerOverlay: View {
    let speedKPH: Int

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.85))
                .frame(width: 65, height: 65)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )

            VStack(spacing: 0) {
                Text("\(speedKPH > 0 ? speedKPH : 65)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("km/h")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }
}

struct VoiceAssistantWidget: View {
    @ObservedObject var coordinator: VoiceAssistantCoordinator
    let onKeyboardTap: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        .frame(width: 56, height: 56)
                        .overlay(
                            Circle()
                                .stroke(Color.blue.opacity(0.3), lineWidth: 3)
                                .blur(radius: 4)
                        )
                    
                    HStack(spacing: 3) {
                        ForEach(0..<5) { i in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.white)
                                .frame(width: 3, height: barHeight(for: i))
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Talk to Kalpana")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                    Text(stateDescription)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.5))
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            HStack(spacing: 12) {
                let isListening = coordinator.state == .listening || coordinator.state == .detectingSpeech
                Button(action: { coordinator.toggleListening() }) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 16))
                        .foregroundColor(isListening ? .black : .white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(isListening ? Color.white : Color.white.opacity(0.08))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(isListening ? 0.8 : 0.15), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Button(action: onKeyboardTap) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Button(action: { coordinator.cancelListening() }) {
                    Image(systemName: "square.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(Color.black.opacity(0.85))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var stateDescription: String {
        switch coordinator.state {
        case .idle: return "I'm listening..."
        case .requestingPermission: return "Requesting mic..."
        case .listening: return "I'm listening..."
        case .detectingSpeech: return "Listening..."
        case .transcribing: return "Processing..."
        case .thinking: return "Thinking..."
        case .awaitingConfirmation: return "Confirm?"
        case .speaking: return "Speaking..."
        case .interrupted: return "Interrupted"
        case .unavailable: return "Unavailable"
        case .failed: return "Failed"
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let isListening = coordinator.state == .listening || coordinator.state == .detectingSpeech
        if !isListening {
            let staticHeights: [CGFloat] = [12, 24, 30, 24, 12]
            return staticHeights[index]
        }
        
        let level = max(0, coordinator.micLevel + 80)
        let normalized = CGFloat(level / 80.0)
        let baseHeight: CGFloat = 8.0
        let maxAddHeight: CGFloat = 26.0
        
        let envelope: [CGFloat] = [0.4, 0.8, 1.0, 0.8, 0.4]
        return baseHeight + normalized * maxAddHeight * envelope[index]
    }
}

struct TripMetricsWidget: View {
    let activeRoute: RouteSnapshot?
    let distanceRemaining: Double
    let navETA: Date

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: "clock")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(durationString)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    Text(etaString)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                }
                Spacer()
            }
            
            Divider().background(Color.white.opacity(0.12))

            HStack(spacing: 14) {
                Image(systemName: "road.lanes")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(distanceRemainingString)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    Text("Remaining")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                }
                Spacer()
            }
            
            Divider().background(Color.white.opacity(0.12))

            HStack(spacing: 14) {
                Image(systemName: "flag")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(destinationString)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    Text("Destination")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                }
                Spacer()
            }
        }
        .padding(16)
        .background(Color.black.opacity(0.85))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var durationString: String {
        if let route = activeRoute {
            let seconds = route.expectedArrival.timeIntervalSinceNow
            let minutes = Int(max(0, seconds / 60))
            if minutes < 60 {
                return "\(minutes) min"
            }
            return "\(minutes / 60) h \(minutes % 60) min"
        }
        return "28 min"
    }

    private var etaString: String {
        if let route = activeRoute {
            return route.expectedArrival.formatted(date: .omitted, time: .shortened) + " ETA"
        }
        return "12:07 PM ETA"
    }

    private var distanceRemainingString: String {
        if distanceRemaining > 0 {
            if distanceRemaining >= 1000 {
                return String(format: "%.1f km", distanceRemaining / 1000)
            } else {
                return "\(Int(distanceRemaining)) m"
            }
        }
        return "12.4 km"
    }

    private var destinationString: String {
        if let route = activeRoute {
            return route.destination.name
        }
        return "NIET"
    }
}

struct YouTubeMusicWidget: View {
    @ObservedObject var model: DashboardViewModel
    @ObservedObject private var nowPlaying: NowPlayingObserver = .shared

    var body: some View {
        Group {
            if nowPlaying.isActive {
                playingView
            } else {
                emptyView
            }
        }
        .background(Color.black.opacity(0.85))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(nowPlaying.isActive ? 0.12 : 0.06), lineWidth: 1)
        )
    }

    // MARK: — Active playback

    @ViewBuilder private var playingView: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                // Artwork
                if let artwork = nowPlaying.trackArtwork {
                    Image(uiImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.blue.opacity(0.15))
                            .frame(width: 64, height: 64)
                        Image(systemName: "music.note")
                            .font(.title)
                            .foregroundColor(.white)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(nowPlaying.trackTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    if !nowPlaying.trackArtist.isEmpty {
                        Text(nowPlaying.trackArtist)
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                    Text("Now Playing")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            // Progress bar — only when duration is reported by the audio session
            if nowPlaying.duration > 0 {
                VStack(spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.15))
                                .frame(height: 4)
                            Capsule()
                                .fill(Color.white)
                                .frame(
                                    width: geo.size.width * CGFloat(
                                        min(1, nowPlaying.elapsed / nowPlaying.duration)
                                    ),
                                    height: 4
                                )
                        }
                    }
                    .frame(height: 4)
                    .padding(.horizontal, 16)

                    HStack {
                        Text(formatTime(nowPlaying.elapsed))
                            .font(.system(size: 10, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                        Spacer()
                        Text(formatTime(nowPlaying.duration))
                            .font(.system(size: 10, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .padding(.horizontal, 16)
                }
            }

            // Playback controls
            HStack(spacing: 36) {
                Button(action: { nowPlaying.previous() }) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)

                Button(action: { nowPlaying.togglePlayPause() }) {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 1.5)
                            .frame(width: 48, height: 48)
                        Image(systemName: nowPlaying.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(.plain)

                Button(action: { nowPlaying.next() }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 16)
        }
    }

    // MARK: — Nothing playing

    private var emptyView: some View {
        VStack(spacing: 10) {
            Image(systemName: "music.note.list")
                .font(.system(size: 28))
                .foregroundColor(.white.opacity(0.2))
            Text("No music playing")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.35))
            Text("Open YouTube Music or Apple Music to begin")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.2))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: — Helpers

    private func formatTime(_ time: TimeInterval) -> String {
        let t = max(0, time)
        let minutes = Int(t) / 60
        let seconds = Int(t) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}


struct NightDriveArt: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.05, blue: 0.15), Color(red: 0.1, green: 0.05, blue: 0.1)],
                startPoint: .top,
                endPoint: .bottom
            )
            
            GeometryReader { geo in
                ForEach(0..<15) { i in
                    Circle()
                        .fill(Color.white.opacity(0.6))
                        .frame(width: 1.5, height: 1.5)
                        .position(
                            x: CGFloat((i * 17) % 64),
                            y: CGFloat((i * 11) % 40)
                        )
                }
            }
            
            Path { path in
                path.move(to: CGPoint(x: 0, y: 40))
                path.addLine(to: CGPoint(x: 64, y: 40))
                path.addLine(to: CGPoint(x: 64, y: 64))
                path.addLine(to: CGPoint(x: 0, y: 64))
                path.closeSubpath()
            }
            .fill(Color(white: 0.08))
            
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.purple.opacity(0.4), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 4)
                .position(x: 32, y: 40)
            
            Path { path in
                path.move(to: CGPoint(x: 32, y: 40))
                path.addLine(to: CGPoint(x: 10, y: 64))
                
                path.move(to: CGPoint(x: 32, y: 40))
                path.addLine(to: CGPoint(x: 54, y: 64))
            }
            .stroke(Color.white.opacity(0.2), lineWidth: 1)
            
            Path { path in
                path.move(to: CGPoint(x: 32, y: 40))
                path.addLine(to: CGPoint(x: 32, y: 64))
            }
            .stroke(Color.yellow.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))

            VStack(spacing: 1) {
                Text("NIGHT")
                    .font(.system(size: 7, weight: .bold, design: .default))
                    .foregroundColor(.white.opacity(0.8))
                Text("DRIVE")
                    .font(.system(size: 5, weight: .regular, design: .default))
                    .foregroundColor(.white.opacity(0.5))
            }
            .position(x: 32, y: 20)
        }
    }
}

private struct HomeSection: View {
    @ObservedObject var model: DashboardViewModel

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 16) {
                LiveMapCard(speedKPH: model.speedKPH, route: model.mapRoute)
                    .frame(maxWidth: .infinity)
                VStack(spacing: 16) {
                    NavigationSummary(route: model.activeRoute)
                    IndependentMusicSummary(model: model)
                    DeviceSummary(model: model)
                }
                .frame(width: geometry.size.width < 900 ? 300 : 370)
            }
        }
    }
}

private struct LiveMapCard: View {
    let speedKPH: Int
    let route: MKRoute?
    @State private var position: MapCameraPosition = .userLocation(followsHeading: true, fallback: .automatic)

    var body: some View {
        DriveCard(insets: 0) {
            ZStack(alignment: .topLeading) {
                Map(position: $position) {
                    UserAnnotation()
                    if let route {
                        MapPolyline(route.polyline).stroke(.primary, lineWidth: 7)
                    }
                }
                .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
                .mapControls {
                    MapCompass()
                    MapScaleView()
                    MapUserLocationButton()
                }

                HStack(alignment: .top) {
                    Label("LIVE MAP", systemImage: "location.fill")
                        .font(.headline)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 46)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8))
                    Spacer()
                    VStack(spacing: 0) {
                        Text(String(speedKPH))
                            .font(.system(size: 52, weight: .black, design: .rounded))
                        Text("KM/H").font(.caption.bold())
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8))
                }
                .padding(14)
            }
        }
    }
}

private struct NavigationSummary: View {
    let route: RouteSnapshot?

    var body: some View {
        DriveCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("NAVIGATION", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.headline)
                if let route {
                    Text(route.destination.name).font(.title2.bold()).lineLimit(2)
                    Text(route.nextInstruction).foregroundStyle(.secondary).lineLimit(2)
                    Text("ETA \(route.expectedArrival.formatted(date: .omitted, time: .shortened))")
                        .font(.headline)
                } else {
                    Text("No active route").font(.title2.bold())
                    Text("Open Map and search for a destination.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct IndependentMusicSummary: View {
    @ObservedObject var model: DashboardViewModel

    var body: some View {
        MiniPlayerView(model: model)
    }
}

private struct DeviceSummary: View {
    @ObservedObject var model: DashboardViewModel

    var body: some View {
        DriveCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("IPAD STATUS", systemImage: "ipad").font(.headline)
                Text(model.batteryStatus).font(.title3.bold())
                Text(model.thermalStatus).foregroundStyle(.secondary)
                Text(model.audioRoute.rawValue.capitalized + " audio").foregroundStyle(.secondary)
            }
        }
    }
}

private struct NavigationMapSection: View {
    @ObservedObject var model: DashboardViewModel
    @State private var position: MapCameraPosition = .userLocation(followsHeading: true, fallback: .automatic)
    @State private var showParkingSheet = false
    @State private var showSavedPlaces = false
    @State private var showAskDrive = false

    var body: some View {
        HStack(spacing: 16) {
            // Left: Map Card
            ZStack(alignment: .topLeading) {
                Map(position: $position) {
                    UserAnnotation {
                        ZStack {
                            Circle()
                                .fill(Color.black)
                                .frame(width: 38, height: 38)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: 2)
                                        .shadow(color: .white.opacity(0.8), radius: 4)
                                )
                            Image(systemName: "location.north.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                                .rotationEffect(.degrees(model.courseDegrees ?? 0))
                        }
                    }

                    if let route = model.mapRoute {
                        MapPolyline(route.polyline)
                            .stroke(Color.white, style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
                    }
                    
                    // Parking marker
                    if let parking = model.parkedLocation {
                        Annotation("Parked Here", coordinate: CLLocationCoordinate2D(
                            latitude: parking.coordinate.latitude,
                            longitude: parking.coordinate.longitude
                        )) {
                            ZStack {
                                Circle().fill(Color.orange).frame(width: 36, height: 36)
                                Image(systemName: "car.fill").foregroundColor(.white).font(.headline)
                            }
                        }
                    }
                }
                .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
                .mapControls {
                    MapCompass()
                    MapScaleView()
                }
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )

                // Navigation TBT and Speedometer overlays
                HStack(alignment: .top, spacing: 12) {
                    TurnByTurnOverlay(
                        nextInstruction: model.navNextInstruction,
                        distanceRemaining: model.navDistanceRemaining,
                        currentStreet: model.navCurrentStreet
                    )
                    
                    SpeedometerOverlay(speedKPH: model.speedKPH)
                }
                .padding(16)
                
                // Floating options menu in top-right
                VStack {
                    HStack {
                        Spacer()
                        Menu {
                            Button(action: { showSavedPlaces = true }) {
                                Label("Saved Places", systemImage: "bookmark.fill")
                            }
                            Button(action: { model.showTripHistory = true }) {
                                Label("Trip History", systemImage: "list.bullet.rectangle")
                            }
                            Button(action: {
                                if model.isTripRecording {
                                    model.stopTripRecording()
                                } else {
                                    model.startTripRecording()
                                }
                            }) {
                                Label(model.isTripRecording ? "Stop Recording" : "Record Trip", systemImage: "record.circle")
                            }
                            Button(action: { showParkingSheet = true }) {
                                Label("Save Parking", systemImage: "car.badge.plus")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.white.opacity(0.8))
                                .background(Circle().fill(Color.black.opacity(0.6)))
                        }
                    }
                    Spacer()
                }
                .padding(16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Right Widget column
            VStack(spacing: 16) {
                VoiceAssistantWidget(coordinator: model.voiceAssistant, onKeyboardTap: {
                    model.voiceAssistant.cancelListening()
                    showAskDrive = true
                })
                
                TripMetricsWidget(
                    activeRoute: model.activeRoute,
                    distanceRemaining: model.navDistanceRemaining,
                    navETA: model.navETA
                )
                
                YouTubeMusicWidget(model: model)
            }
            .frame(width: 380)
        }
        .sheet(isPresented: $showAskDrive) {
            AskDriveView(model: model)
        }
        // Parking auto-prompt
        .alert("Save Parking Location?", isPresented: Binding(
            get: { model.showsParkingPrompt },
            set: { _ in model.dismissParkingPrompt() }
        )) {
            Button("Save") { model.acceptParkingPrompt() }
            Button("Dismiss", role: .cancel) { model.dismissParkingPrompt() }
        } message: {
            Text("It looks like you have stopped. Do you want to save your parking location?")
        }
        // Parking sheet
        .sheet(isPresented: $showParkingSheet) {
            ParkingSheet(model: model)
        }
        // Saved places sheet
        .sheet(isPresented: $showSavedPlaces) {
            SavedPlacesSheet(model: model)
        }
        // Trip history sheet
        .sheet(isPresented: $model.showTripHistory) {
            TripHistorySheet(model: model)
        }
    }
}

// MARK: Parking Sheet
private struct ParkingSheet: View {
    @ObservedObject var model: DashboardViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Parking Details")) {
                    TextField("Note (e.g. near elevator)", text: $model.parkingNote)
                    TextField("Floor (e.g. B2)", text: $model.parkingFloor)
                    TextField("Slot (e.g. A-21)", text: $model.parkingSlot)
                }
                Section {
                    Button("Save Parking Location") {
                        model.saveCurrentParking()
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Save Parking")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: Saved Places Sheet
private struct SavedPlacesSheet: View {
    @ObservedObject var model: DashboardViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if !model.savedPlaces.isEmpty {
                    Section(header: Text("Saved Places")) {
                        ForEach(model.savedPlaces) { place in
                            HStack {
                                Image(systemName: savedPlaceIcon(place.label))
                                    .foregroundStyle(.blue)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(place.name).font(.headline)
                                    Text(place.address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Button {
                                    model.startNavigation(to: Destination(
                                        name: place.name,
                                        address: place.address,
                                        coordinate: place.coordinate,
                                        kind: .favourite
                                    ))
                                    dismiss()
                                } label: {
                                    Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .onDelete { offsets in
                            offsets.forEach { i in
                                model.deleteSavedPlace(id: model.savedPlaces[i].id)
                            }
                        }
                    }
                }

                if !model.recentDestinations.isEmpty {
                    Section(header: Text("Recents")) {
                        ForEach(model.recentDestinations) { dest in
                            HStack {
                                Image(systemName: "clock").foregroundStyle(.secondary).frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(dest.name).font(.headline)
                                    Text(dest.address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Button {
                                    model.startNavigation(to: dest)
                                    dismiss()
                                } label: {
                                    Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                    Section {
                        Button("Clear Recent Destinations", role: .destructive) {
                            model.clearRecentDestinations()
                        }
                    }
                }

                if model.savedPlaces.isEmpty && model.recentDestinations.isEmpty {
                    ContentUnavailableView("No Saved Places", systemImage: "bookmark",
                        description: Text("Saved places will appear here. Search for a location and mark it as Home, Work, or a custom place."))
                }
            }
            .navigationTitle("Places")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .presentationDetents([.large])
    }

    private func savedPlaceIcon(_ label: SavedPlaceLabel) -> String {
        switch label {
        case .home: return "house.fill"
        case .work: return "briefcase.fill"
        case .college: return "building.columns.fill"
        case .custom: return "bookmark.fill"
        }
    }
}

// MARK: Trip History Sheet
private struct TripHistorySheet: View {
    @ObservedObject var model: DashboardViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if model.trips.isEmpty {
                    ContentUnavailableView(
                        "No Trips Recorded",
                        systemImage: "car.rear.road.lane",
                        description: Text("Tap \"Record Trip\" on the map to start tracking a drive. Your trip history will appear here.")
                    )
                } else {
                    List {
                        ForEach(model.trips.reversed()) { trip in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(trip.startTime.formatted(date: .abbreviated, time: .shortened))
                                        .font(.headline)
                                    Spacer()
                                    if trip.isPrivate {
                                        Label("Private", systemImage: "eye.slash").font(.caption)
                                    }
                                }
                                HStack(spacing: 18) {
                                    Label(String(format: "%.1f km", trip.distanceMetres / 1000), systemImage: "road.lanes")
                                    Label(durationString(trip.durationSeconds), systemImage: "clock")
                                    Label(String(format: "%.0f km/h avg", trip.averageSpeedKPH), systemImage: "speedometer")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                if !trip.notes.isEmpty {
                                    Text(trip.notes).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    model.deleteTripLog(id: trip.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Trip History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .presentationDetents([.large])
    }

    private func durationString(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}

private struct MusicSection: View {
    @ObservedObject var model: DashboardViewModel

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Label("INDEPENDENT IPAD MEDIA", systemImage: "ipad.and.arrow.forward")
                    .font(.headline)
                Spacer()
                Text("Audio route: \(model.audioRoute.rawValue.capitalized)")
                    .font(.subheadline.bold())
            }
            YouTubeMusicView()
        }
    }
}

private struct PhoneSection: View {
    @ObservedObject var model: DashboardViewModel
    @State private var selectedContact: KalpanaContact?
    @State private var filterTab: FilterTab = .all

    enum FilterTab: String, CaseIterable, Identifiable {
        case all = "All"
        case favourites = "Favourites"
        case recents = "Recents"
        var id: Self { self }
    }

    var body: some View {
        HStack(spacing: 16) {
            // Left Pane: Contact Directory
            VStack(spacing: 12) {
                HStack {
                    Label("NATIVE IPAD CONTACTS", systemImage: "person.2.fill")
                        .font(.headline)
                    Spacer()
                    Text("Permission: \(model.contactsPermissionStatus)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Check authorization status
                if model.contactsPermissionStatus == "Denied" || model.contactsPermissionStatus == "Restricted" {
                    permissionDeniedView
                } else if model.contactsPermissionStatus == "Not Determined" {
                    permissionRequestView
                } else {
                    contactsListView
                }
            }
            .frame(maxWidth: .infinity)

            // Right Pane: Detail & Keypad
            VStack(spacing: 16) {
                if let contact = selectedContact {
                    contactDetailView(contact)
                } else {
                    keypadAndManualDialView
                }
            }
            .frame(width: 380)
        }
        .onAppear {
            if model.contactsPermissionStatus == "Authorized" {
                model.fetchNativeContacts()
            }
        }
    }

    private var permissionRequestView: some View {
        DriveCard {
            VStack(spacing: 16) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 60))
                Text("Contacts Permission Required")
                    .font(.title2.bold())
                Text("Kalpana Drive uses contacts stored on this iPad to let you search people and start calls.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Enable Contacts") {
                    model.requestContactsPermission()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var permissionDeniedView: some View {
        DriveCard {
            VStack(spacing: 16) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 60))
                Text("Contacts Access Disabled")
                    .font(.title2.bold())
                Text("Please enable Contacts access in the iPad System Settings to view and call your contacts.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var contactsListView: some View {
        VStack(spacing: 10) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search by name, organization, or phone number", text: $model.contactQuery)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        model.updateContactQuery(model.contactQuery)
                    }
                if !model.contactQuery.isEmpty {
                    Button(action: { model.contactQuery = "" }) {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color.primary.opacity(0.06))
            .cornerRadius(8)

            // Segmented filter
            Picker("Filter", selection: $filterTab) {
                ForEach(FilterTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            // Contact list
            let list = contactsForCurrentTab
            if list.isEmpty {
                DriveCard {
                    VStack(spacing: 8) {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .font(.system(size: 40))
                        Text("No Contacts Found")
                            .font(.headline)
                        Text(model.contactQuery.isEmpty ? "Your contacts directory is empty." : "No contacts matched your search.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(list) { contact in
                            Button {
                                selectedContact = contact
                            } label: {
                                HStack(spacing: 12) {
                                    // Initials or Photo
                                    contactPhotoOrInitials(contact: contact, size: 48)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(contact.displayName)
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                        if !contact.organisation.isEmpty {
                                            Text(contact.organisation)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    if contact.isFavourite {
                                        Image(systemName: "star.fill")
                                            .foregroundColor(.yellow)
                                    }
                                    Image(systemName: "chevron.right")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                }
                                .padding(10)
                                .background(selectedContact?.id == contact.id ? Color.primary.opacity(0.12) : Color.primary.opacity(0.04))
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var contactsForCurrentTab: [KalpanaContact] {
        switch filterTab {
        case .all:
            return model.filteredContacts
        case .favourites:
            let query = model.contactQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            let favs = model.nativeFavourites
            if query.isEmpty { return favs }
            return favs.filter {
                $0.displayName.localizedCaseInsensitiveContains(query) ||
                $0.organisation.localizedCaseInsensitiveContains(query)
            }
        case .recents:
            let query = model.contactQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            let recents = model.recentCalls
            if query.isEmpty { return recents }
            return recents.filter {
                $0.displayName.localizedCaseInsensitiveContains(query) ||
                $0.organisation.localizedCaseInsensitiveContains(query)
            }
        }
    }

    @ViewBuilder
    private func contactPhotoOrInitials(contact: KalpanaContact, size: CGFloat) -> some View {
        Group {
            if let imgData = contact.thumbnailImageData, let uiImage = UIImage(data: imgData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(contact.initials)
                    .font(.system(size: size * 0.4, weight: .bold))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.primary.opacity(0.15))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.primary.opacity(0.5), lineWidth: 1))
    }

    @ViewBuilder
    private func contactDetailView(_ contact: KalpanaContact) -> some View {
        DriveCard {
            VStack(spacing: 16) {
                // Header: Back button & Star
                HStack {
                    Button(action: { selectedContact = nil }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .font(.headline)
                    }
                    Spacer()
                    Button(action: {
                        model.toggleFavourite(for: contact)
                        // Update local state copy
                        var updated = contact
                        updated.isFavourite.toggle()
                        selectedContact = updated
                    }) {
                        Image(systemName: contact.isFavourite ? "star.fill" : "star")
                            .font(.title2)
                            .foregroundColor(contact.isFavourite ? .yellow : .primary)
                    }
                }

                // Photo, Name, Organization
                contactPhotoOrInitials(contact: contact, size: 90)
                
                VStack(spacing: 4) {
                    Text(contact.displayName)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    if !contact.organisation.isEmpty {
                        Text(contact.organisation)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }

                Divider()

                // Phone Numbers list with Call Buttons
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(contact.phoneNumbers, id: \.self) { phone in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(phone.label.uppercased())
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                HStack {
                                    Text(phone.number)
                                        .font(.title3.bold())
                                    Spacer()
                                    Button(action: {
                                        model.call(number: phone.number, contactId: contact.id)
                                    }) {
                                        Image(systemName: "phone.fill")
                                            .font(.headline)
                                            .padding(12)
                                            .background(Color.primary)
                                            .foregroundColor(Color(white: 0.1))
                                            .clipShape(Circle())
                                    }
                                }
                            }
                            .padding(10)
                            .background(Color.primary.opacity(0.05))
                            .cornerRadius(8)
                        }
                    }
                }
            }
        }
    }

    private var keypadAndManualDialView: some View {
        DriveCard {
            VStack(spacing: 14) {
                // Dialer display
                HStack {
                    Text(model.phoneNumberToDial)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Spacer()
                    if !model.phoneNumberToDial.isEmpty {
                        Button(action: {
                            model.phoneNumberToDial.removeLast()
                        }) {
                            Image(systemName: "delete.left.fill")
                                .font(.title)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(height: 50)
                .padding(.horizontal, 12)
                .background(Color.primary.opacity(0.06))
                .cornerRadius(8)

                // Keypad grid (3x4)
                let keys = [
                    ["1", "2", "3"],
                    ["4", "5", "6"],
                    ["7", "8", "9"],
                    ["*", "0", "#"]
                ]

                VStack(spacing: 10) {
                    ForEach(keys, id: \.self) { row in
                        HStack(spacing: 10) {
                            ForEach(row, id: \.self) { key in
                                Button(action: {
                                    model.phoneNumberToDial.append(key)
                                }) {
                                    Text(key)
                                        .font(.system(size: 26, weight: .bold, design: .rounded))
                                        .frame(maxWidth: .infinity, minHeight: 52)
                                        .background(Color.primary.opacity(0.08))
                                        .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                // Call button
                Button(action: {
                    model.callPhoneNumber()
                }) {
                    HStack {
                        Image(systemName: "phone.fill")
                        Text("Call Number")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(model.phoneNumberToDial.isEmpty ? Color.secondary.opacity(0.3) : Color.primary)
                    .foregroundColor(model.phoneNumberToDial.isEmpty ? .secondary : Color(white: 0.1))
                    .cornerRadius(8)
                }
                .disabled(model.phoneNumberToDial.isEmpty)
            }
        }
    }
}

private struct SettingsSection: View {
    @ObservedObject var model: DashboardViewModel
    @State private var newAvoidRoad = ""
    @State private var apiKeyInput = KeychainHelper.shared.loadKeychainApiKey() ?? ""
    @State private var apiKeySaveStatus = ""

    var body: some View {
        DriveCard(insets: 0) {
            ScrollView {
                VStack(spacing: 28) {
                    HStack {
                        Label("SETTINGS", systemImage: "gearshape.fill").font(.headline)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)

                    // Appearance
                    settingsGroup(title: "Appearance", icon: "circle.lefthalf.filled") {
                        Picker("Appearance", selection: Binding(
                            get: { model.appearance },
                            set: { model.setAppearance($0) }
                        )) {
                            Text("Day").tag(DriveAppearance.day)
                            Text("Night").tag(DriveAppearance.night)
                            Text("High Sunlight").tag(DriveAppearance.highSunlight)
                        }
                        .pickerStyle(.segmented)
                    }

                    // Map Style
                    settingsGroup(title: "Map Style", icon: "map") {
                        Picker("Map Style", selection: $model.mapStyle) {
                            ForEach(DriveMapStyle.allCases) { style in
                                Label(style.rawValue, systemImage: style.icon).tag(style)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    // Route Intelligence
                    settingsGroup(title: "Route Intelligence", icon: "road.lanes") {
                        Toggle("Avoid Toll Roads", isOn: Binding(
                            get: { model.avoidTolls },
                            set: { model.setAvoidTolls($0) }
                        ))
                        Toggle("Avoid Highways", isOn: Binding(
                            get: { model.avoidHighways },
                            set: { model.setAvoidHighways($0) }
                        ))
                        if !model.roadPreferences.isEmpty {
                            Divider()
                            Text("Road Preferences").font(.subheadline.bold())
                            ForEach(model.roadPreferences, id: \.roadName) { pref in
                                HStack {
                                    Image(systemName: pref.preferenceType == .avoid ? "minus.circle.fill" : "checkmark.circle.fill")
                                        .foregroundStyle(pref.preferenceType == .avoid ? .red : .green)
                                    Text(pref.roadName)
                                    Spacer()
                                    Button(action: { model.deleteRoadPreference(pref.roadName) }) {
                                        Image(systemName: "trash").foregroundStyle(.red)
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                        Divider()
                        HStack(spacing: 8) {
                            TextField("Road name to avoid", text: $newAvoidRoad)
                                .textFieldStyle(.roundedBorder)
                            Button("Avoid") {
                                let name = newAvoidRoad.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !name.isEmpty else { return }
                                model.avoidRoad(name)
                                newAvoidRoad = ""
                            }
                            .buttonStyle(.bordered)
                            .disabled(newAvoidRoad.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }

                    // Vehicle Profile
                    settingsGroup(title: "Vehicle Profile — Maruti Ignis", icon: "fuelpump.fill") {
                        Picker("Fuel Type", selection: Binding(
                            get: { model.ignisFuelType },
                            set: { model.setIgnisFuelType($0) }
                        )) {
                            ForEach(RouteIntelligenceService.IgnisFuelType.allCases) { type in
                                Text(type.rawValue).tag(type)
                            }
                        }
                        .pickerStyle(.segmented)
                        Text("Fuel type is used for range estimation and CNG station proximity warnings.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    // Voice Assistant Language
                    settingsGroup(title: "Voice Assistant Language", icon: "bubble.left.and.exclamationmark.bubble.right.fill") {
                        VStack(alignment: .leading, spacing: 10) {
                            Picker("Language", selection: Binding(
                                get: { model.voiceAssistant.speechRecognition.selectedLanguage },
                                set: { model.voiceAssistant.speechRecognition.selectedLanguage = $0 }
                            )) {
                                ForEach(SpeechRecognitionService.LanguageMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            
                            if model.voiceAssistant.speechRecognition.selectedLanguage == .hinglish {
                                Text("Hinglish mode is experimental. Accent recognition and command accuracy may vary.")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }

                    // Siri
                    settingsGroup(title: "Siri Commands", icon: "waveform.circle") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("• \"Open YouTube Music in Kalpana Drive\"")
                            Text("• \"Open the map in Kalpana Drive\"")
                            Text("• \"Search for India Gate in Kalpana Drive\"")
                            Text("Activate Siri by voice or the iPad's top button. Siri appears as a system overlay.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    // AI Assistant Provider (NVIDIA NIM)
                    settingsGroup(title: "AI Assistant Provider (NVIDIA NIM)", icon: "key.fill") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Status:")
                                    .font(.subheadline)
                                if KeychainHelper.shared.localOnlyMode {
                                    Text("Local-only")
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.orange)
                                } else if let key = KeychainHelper.shared.loadKeychainApiKey(), !key.isEmpty {
                                    Text("Active (Key Saved)")
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.green)
                                } else {
                                    Text("Not Configured")
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.red)
                                }
                            }
                            
                            SecureField("Enter NVIDIA API Key", text: $apiKeyInput)
                                .textFieldStyle(.roundedBorder)
                            
                            HStack(spacing: 12) {
                                Button("Save Key") {
                                    if KeychainHelper.shared.saveApiKey(apiKeyInput) {
                                        apiKeySaveStatus = "Key saved successfully."
                                    } else {
                                        apiKeySaveStatus = "Failed to save key."
                                    }
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Delete Key", role: .destructive) {
                                    KeychainHelper.shared.deleteApiKey()
                                    apiKeyInput = ""
                                    apiKeySaveStatus = "Key deleted."
                                }
                                .buttonStyle(.bordered)
                                .disabled(apiKeyInput.isEmpty)
                                
                                Button("Test Connection") {
                                    apiKeySaveStatus = "Testing connection..."
                                    Task {
                                        let result = await model.aiCoordinator.testConnection(with: apiKeyInput)
                                        apiKeySaveStatus = result.message
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(apiKeyInput.isEmpty)
                            }
                            
                            Toggle("Force Local-only Mode", isOn: Binding(
                                get: { KeychainHelper.shared.localOnlyMode },
                                set: { KeychainHelper.shared.localOnlyMode = $0 }
                            ))
                            
                            if !apiKeySaveStatus.isEmpty {
                                Text(apiKeySaveStatus)
                                    .font(.caption)
                                    .foregroundStyle(apiKeySaveStatus.contains("succeeded") || apiKeySaveStatus.contains("success") ? .green : .red)
                            }
                            
                            Text("The API key is securely saved to the iOS Keychain and never printed or logged. Treat the previously exposed key as compromised. Revoke it on the NVIDIA developer portal.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button("Open System Health") { model.openDiagnostics() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .padding(.bottom, 18)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func settingsGroup<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon).font(.headline).foregroundStyle(.secondary)
            content()
        }
        .padding(.horizontal, 20)
    }
}


enum DriveMapStyle: String, CaseIterable, Identifiable {
    case standard = "Standard"
    case satellite = "Satellite"
    case hybrid = "Hybrid"
    var id: Self { self }
    var icon: String {
        switch self {
        case .standard: return "map"
        case .satellite: return "globe.americas.fill"
        case .hybrid: return "map.fill"
        }
    }
}

struct DriveCard<Content: View>: View {
    let insets: CGFloat
    @ViewBuilder let content: Content

    init(insets: CGFloat = 18, @ViewBuilder content: () -> Content) {
        self.insets = insets
        self.content = content()
    }

    var body: some View {
        content
            .padding(insets)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct DrivePalette {
    let appearance: DriveAppearance
    var background: Color { appearance == .day ? Color(hue: 0.62, saturation: 0.05, brightness: 0.97) : Color(hue: 0.62, saturation: 0.15, brightness: 0.06) }
    var foreground: Color { appearance == .day ? .black : .white }
    var card: Color { appearance == .day ? Color(white: 0.92) : Color(white: 0.10) }
    var border: Color { foreground.opacity(0.75) }
}

// MARK: - Liquid Glass Background

/// Animated gradient mesh background that shifts through aurora-like hues.
struct LiquidGlassBackground: View {
    let appearance: DriveAppearance
    @State private var phase: Double = 0

    private var isDark: Bool { appearance == .night }

    var body: some View {
        Group {
            if #available(iOS 18.0, *) {
                TimelineView(.animation(minimumInterval: 1/30)) { ctx in
                    MeshGradient(
                        width: 3,
                        height: 3,
                        points: animatedPoints(at: ctx.date.timeIntervalSinceReferenceDate),
                        colors: animatedColors(at: ctx.date.timeIntervalSinceReferenceDate)
                    )
                }
            } else {
                TimelineView(.animation(minimumInterval: 1/30)) { ctx in
                    LinearGradient(
                        colors: animatedColors(at: ctx.date.timeIntervalSinceReferenceDate),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
        }
        .ignoresSafeArea()
    }

    private func animatedPoints(at t: Double) -> [SIMD2<Float>] {
        let s = Float(sin(t * 0.25)) * 0.08
        let c = Float(cos(t * 0.18)) * 0.06
        return [
            [0, 0],       [0.5 + s, 0],    [1, 0],
            [0, 0.5 + c], [0.5, 0.5],      [1, 0.5 + s],
            [0, 1],       [0.5 - c, 1],    [1, 1]
        ]
    }

    private func animatedColors(at t: Double) -> [Color] {
        let pulse = (sin(t * 0.3) + 1) / 2  // 0…1
        if isDark {
            // Deep saturated colours — glass needs vivid background to look translucent
            return [
                Color(hue: 0.62, saturation: 0.80, brightness: 0.28 + pulse * 0.08),
                Color(hue: 0.72, saturation: 0.75, brightness: 0.35 + pulse * 0.10),
                Color(hue: 0.55, saturation: 0.70, brightness: 0.22),
                Color(hue: 0.65, saturation: 0.85, brightness: 0.30),
                Color(hue: 0.80, saturation: 0.60, brightness: 0.38),
                Color(hue: 0.58, saturation: 0.75, brightness: 0.25),
                Color(hue: 0.75, saturation: 0.80, brightness: 0.20 + pulse * 0.06),
                Color(hue: 0.63, saturation: 0.70, brightness: 0.32),
                Color(hue: 0.68, saturation: 0.78, brightness: 0.28)
            ]
        } else {
            return [
                Color(hue: 0.57, saturation: 0.45, brightness: 0.92 - pulse * 0.05),
                Color(hue: 0.62, saturation: 0.50, brightness: 0.95),
                Color(hue: 0.52, saturation: 0.40, brightness: 0.90),
                Color(hue: 0.60, saturation: 0.48, brightness: 0.88),
                Color(hue: 0.68, saturation: 0.35, brightness: 0.96),
                Color(hue: 0.55, saturation: 0.42, brightness: 0.93),
                Color(hue: 0.63, saturation: 0.50, brightness: 0.89 + pulse * 0.04),
                Color(hue: 0.58, saturation: 0.38, brightness: 0.94),
                Color(hue: 0.70, saturation: 0.45, brightness: 0.91)
            ]
        }
    }
}

extension View {
    func sectionVisibility(isVisible: Bool) -> some View {
        self
            .opacity(isVisible ? 1 : 0)
            .zIndex(isVisible ? 1 : 0)
            .allowsHitTesting(isVisible)
            .accessibilityHidden(!isVisible)
    }
}

// Stub structures to compile iOS 26+ .glassEffect API on older SDK targets (iOS 17+)
struct GlassEffectStyleStub {
    static let regular = GlassEffectStyleStub()
    func tint(_ color: Color) -> GlassEffectStyleStub {
        self
    }
}

extension View {
    func glassEffect<S: Shape>(_ style: GlassEffectStyleStub, in shape: S) -> some View {
        self.background(.ultraThinMaterial, in: shape)
    }
}
