import Combine
import KalpanaDriveCore
import MapKit
import SwiftUI
import UIKit

struct DashboardView: View {
    @ObservedObject var model: DashboardViewModel
    @State private var showSiriHelp = false

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            VStack(spacing: 16) {
                StatusBar(model: model, palette: palette)
                if let error = model.errorMessage {
                    ErrorBanner(message: error, dismiss: model.clearError)
                }
                content
                BottomNavigation(
                    model: model,
                    palette: palette,
                    openSiriHelp: { showSiriHelp = true }
                )
            }
            .padding(20)
        }
        .foregroundStyle(palette.foreground)
        .sheet(isPresented: $model.isDiagnosticsPresented) {
            DiagnosticsView(model: model)
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
        switch model.selectedSection {
        case .home:
            HomeSection(model: model)
        case .map:
            NavigationMapSection(model: model)
        case .music:
            MusicSection(model: model)
        case .phone:
            PhoneSection(model: model)
        case .settings:
            SettingsSection(model: model)
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
            StatusPill(text: model.drivingState.rawValue, prominent: model.drivingState.restrictsInteraction, palette: palette)
            StatusPill(text: "GPS: \(model.locationAccuracy)", palette: palette)
            StatusPill(text: "AUDIO: \(model.audioRoute.rawValue.uppercased())", palette: palette)
            StatusPill(text: model.isOnline ? "ONLINE" : "OFFLINE", prominent: !model.isOnline, palette: palette)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct StatusPill: View {
    let text: String
    var prominent = false
    let palette: DrivePalette

    var body: some View {
        Text(text)
            .font(.caption.bold())
            .padding(.horizontal, 12)
            .frame(minHeight: 42)
            .background(prominent ? palette.foreground : palette.card)
            .foregroundStyle(prominent ? palette.background : palette.foreground)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.border, lineWidth: 2))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message).font(.headline).lineLimit(2)
            Spacer()
            Button("Dismiss", action: dismiss).buttonStyle(.bordered)
        }
        .padding(14)
        .background(Color.primary.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary, lineWidth: 2))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct BottomNavigation: View {
    @ObservedObject var model: DashboardViewModel
    let palette: DrivePalette
    let openSiriHelp: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ForEach(DashboardSection.allCases) { section in
                Button {
                    model.selectSection(section)
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: icon(for: section))
                        Text(section.rawValue)
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(model.selectedSection == section ? palette.foreground : palette.card)
                    .foregroundStyle(model.selectedSection == section ? palette.background : palette.foreground)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }

            Button(action: openSiriHelp) {
                VStack(spacing: 5) {
                    Image(systemName: "waveform.circle.fill")
                    Text("Siri")
                }
                .font(.headline)
                .frame(width: 138, height: 64)
                .background(palette.foreground)
                .foregroundStyle(palette.background)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows Siri commands available for Kalpana Drive")
        }
    }

    private func icon(for section: DashboardSection) -> String {
        switch section {
        case .home: "house.fill"
        case .map: "map.fill"
        case .music: "play.rectangle.fill"
        case .phone: "phone.fill"
        case .settings: "gearshape.fill"
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
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Spacer()
                    VStack(spacing: 0) {
                        Text(String(speedKPH))
                            .font(.system(size: 52, weight: .black, design: .rounded))
                        Text("KM/H").font(.caption.bold())
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
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
        DriveCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("IPAD MUSIC", systemImage: "play.rectangle.fill").font(.headline)
                Text("YouTube Music")
                    .font(.title2.bold())
                Text("Search and play directly on this iPad from the Music section.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Open Music") {
                    model.selectSection(.music)
                }
                .buttonStyle(.borderedProminent)
            }
        }
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

    private var typingBlocked: Bool {
        switch model.drivingState {
        case .moving, .emergency, .thermalLimit, .lowPower:
            true
        default:
            false
        }
    }

    var body: some View {
        DriveCard(insets: 0) {
            ZStack(alignment: .top) {
                Map(position: $position) {
                    UserAnnotation()
                    if let route = model.mapRoute {
                        MapPolyline(route.polyline).stroke(.primary, lineWidth: 8)
                    }
                    ForEach(Array(model.alternativeRoutes.enumerated()), id: \.offset) { item in
                        MapPolyline(item.element.polyline).stroke(.secondary.opacity(0.65), lineWidth: 4)
                    }
                }
                .mapStyle(.standard(elevation: .realistic))
                .mapControls {
                    MapCompass()
                    MapScaleView()
                    MapUserLocationButton()
                }

                VStack(spacing: 10) {
                    searchControls
                    Spacer()
                    routeControls
                }
                .padding(14)
            }
        }
    }

    @ViewBuilder
    private var searchControls: some View {
        if typingBlocked {
            Text("Destination typing is unavailable while driving. Say “Siri, search for <place> in Kalpana Drive”.")
                .font(.headline)
                .padding(14)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    TextField("Search any place, landmark, business, or address", text: $model.destinationQuery)
                        .textFieldStyle(.plain)
                        .font(.title3.bold())
                        .submitLabel(.search)
                        .onSubmit { model.searchDestinations() }
                    Button {
                        model.searchDestinations()
                    } label: {
                        Group {
                            if model.isSearching {
                                ProgressView()
                            } else {
                                Image(systemName: "magnifyingglass").font(.title2.bold())
                            }
                        }
                        .frame(width: 54, height: 54)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.destinationQuery.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                }
                .padding(.horizontal, 16)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                if !model.searchResults.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(model.searchResults.prefix(6))) { result in
                            Button {
                                model.startNavigation(to: result)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(result.name).font(.headline).lineLimit(1)
                                        Text(result.address).font(.caption).lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                                }
                                .frame(minHeight: 58)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                    .padding(.horizontal, 16)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    @ViewBuilder
    private var routeControls: some View {
        if let route = model.activeRoute {
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(route.nextInstruction).font(.title2.bold()).lineLimit(2)
                    Text("\(distance(route.distanceRemainingMetres)) • ETA \(route.expectedArrival.formatted(date: .omitted, time: .shortened))")
                        .font(.headline)
                }
                Spacer()
                Button("Cancel Route") { model.cancelNavigation() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            .padding(16)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func distance(_ metres: Double) -> String {
        if metres >= 1_000 {
            return String(format: "%.1f km", metres / 1_000)
        }
        return "\(Int(metres.rounded())) m"
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

    var body: some View {
        DriveCard {
            VStack(spacing: 18) {
                Image(systemName: model.iphoneConnected ? "iphone.gen2.radiowaves.left.and.right" : "phone")
                    .font(.system(size: 70, weight: .bold))
                Text(model.iphoneConnected ? "iPhone companion connected" : "iPad standalone mode")
                    .font(.system(size: 34, weight: .bold))
                Text(phoneDescription)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 780)

                if let peer = model.iphoneBridge.pendingPeer {
                    HStack {
                        Text("Allow connection from \(peer.displayName)?").font(.headline)
                        Button("Reject") { model.rejectIPhoneConnection() }.buttonStyle(.bordered)
                        Button("Approve") { model.approveIPhoneConnection() }.buttonStyle(.borderedProminent)
                    }
                }

                if model.iphoneConnected {
                    Text("\(model.iphoneContacts.count) contacts received")
                        .font(.headline)
                    Button("Disconnect iPhone") { model.disconnectIPhone() }
                        .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var phoneDescription: String {
        if model.iphoneConnected {
            return "The iPad remains fully usable by itself. The iPhone connection only adds optional contacts and Apple Music control."
        }
        return "Navigation, YouTube Music, Siri shortcuts, GPS, battery, and diagnostics work without an iPhone. Calls and iPhone contacts can be added later through the companion."
    }
}

private struct SettingsSection: View {
    @ObservedObject var model: DashboardViewModel

    var body: some View {
        DriveCard {
            VStack(spacing: 22) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 68, weight: .bold))
                Text("Kalpana Drive Settings")
                    .font(.system(size: 36, weight: .bold))

                Picker("Appearance", selection: Binding(
                    get: { model.appearance },
                    set: { model.setAppearance($0) }
                )) {
                    Text("Day").tag(DriveAppearance.day)
                    Text("Night").tag(DriveAppearance.night)
                    Text("High sunlight").tag(DriveAppearance.highSunlight)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 620)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Siri commands").font(.title2.bold())
                    Text("• “Open YouTube Music in Kalpana Drive”")
                    Text("• “Open the map in Kalpana Drive”")
                    Text("• “Search for India Gate in Kalpana Drive”")
                    Text("Siri is a system overlay. Apps cannot programmatically press or embed Siri, so activate it by voice or with the iPad’s top button.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 720, alignment: .leading)

                Button("Open System Health") {
                    model.openDiagnostics()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.drivingState.restrictsInteraction)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            .background(Color.primary.opacity(0.07))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.8), lineWidth: 2))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct DrivePalette {
    let appearance: DriveAppearance
    var background: Color { appearance == .day ? .white : .black }
    var foreground: Color { appearance == .day ? .black : .white }
    var card: Color { appearance == .day ? Color(white: 0.92) : Color(white: 0.10) }
    var border: Color { foreground.opacity(0.75) }
}
