import KalpanaDriveCore
import MapKit
import SwiftUI

struct DashboardView: View {
    @ObservedObject var model: DashboardViewModel

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            VStack(spacing: 16) {
                StatusBar(model: model, palette: palette)
                if let error = model.errorMessage {
                    ErrorBanner(message: error, dismiss: model.clearError)
                }
                content
                BottomNavigation(model: model, palette: palette)
            }
            .padding(20)
        }
        .foregroundStyle(palette.foreground)
        .sheet(isPresented: $model.isDiagnosticsPresented) {
            DiagnosticsView(model: model)
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
            StatusPill(text: model.iphoneConnected ? "IPHONE CONNECTED" : "IPHONE OFFLINE", prominent: !model.iphoneConnected, palette: palette)
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

            Button {
                model.activateVoice()
            } label: {
                VStack(spacing: 5) {
                    Image(systemName: model.isVoiceActive ? "waveform" : "mic.fill")
                    Text(model.isVoiceActive ? "Listening" : "Kalpana")
                }
                .font(.headline)
                .frame(width: 138, height: 64)
                .background(palette.foreground)
                .foregroundStyle(palette.background)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
    }

    private func icon(for section: DashboardSection) -> String {
        switch section {
        case .home: "house.fill"
        case .map: "map.fill"
        case .music: "music.note"
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
                    NavigationCard(route: model.activeRoute)
                    MediaSummaryCard(model: model)
                    PhoneSummaryCard(model: model)
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

private struct NavigationMapSection: View {
    @ObservedObject var model: DashboardViewModel
    @State private var position: MapCameraPosition = .userLocation(followsHeading: true, fallback: .automatic)

    var body: some View {
        DriveCard(insets: 0) {
            ZStack(alignment: .top) {
                map
                VStack(spacing: 10) {
                    searchControls
                    Spacer()
                    routeControls
                }
                .padding(14)
            }
        }
    }

    private var map: some View {
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
    }

    @ViewBuilder
    private var searchControls: some View {
        if model.drivingState.restrictsInteraction {
            Text("Destination typing is unavailable while driving. Use Kalpana voice control.")
                .font(.headline)
                .padding(14)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    TextField("Search a place or address", text: $model.destinationQuery)
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
                }
                .padding(.horizontal, 16)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                if !model.searchResults.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(model.searchResults.prefix(5))) { result in
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

private struct NavigationCard: View {
    let route: RouteSnapshot?

    var body: some View {
        DriveCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("NAVIGATION", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.headline)
                if let route, route.isActive {
                    Text(route.nextInstruction).font(.title2.bold()).lineLimit(2)
                    HStack {
                        Text(route.destination.name)
                        Spacer()
                        Text(route.expectedArrival, format: .dateTime.hour().minute())
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                } else {
                    Text("No active route").font(.title2.bold())
                    Text("Open Map and choose a real destination.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct MediaSummaryCard: View {
    @ObservedObject var model: DashboardViewModel

    private var title: String {
        if model.iphoneConnected {
            return model.iphoneMedia.title ?? "iPhone Apple Music"
        }
        return model.media.title.isEmpty ? "Nothing playing" : model.media.title
    }

    private var subtitle: String {
        if model.iphoneConnected {
            return model.iphoneMedia.artist ?? "Nothing playing on iPhone"
        }
        return model.media.title.isEmpty ? "iPad Apple Music" : model.media.artist
    }

    private var isPlaying: Bool {
        model.iphoneConnected ? model.iphoneMedia.isPlaying : model.media.isPlaying
    }

    var body: some View {
        DriveCard {
            HStack(spacing: 14) {
                Image(systemName: "music.note")
                    .font(.system(size: 32, weight: .bold))
                    .frame(width: 58, height: 58)
                    .background(Color.primary.opacity(0.12))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline).lineLimit(1)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button {
                    if model.iphoneConnected {
                        model.toggleIPhonePlayback()
                    } else {
                        model.togglePlayback()
                    }
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2.bold())
                        .frame(width: 58, height: 58)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

private struct PhoneSummaryCard: View {
    @ObservedObject var model: DashboardViewModel

    var body: some View {
        DriveCard {
            HStack {
                Image(systemName: model.iphoneConnected ? "iphone.gen2" : "iphone.gen2.slash")
                    .font(.title)
                VStack(alignment: .leading, spacing: 4) {
                    Text(phoneName).font(.headline)
                    Text(phoneSubtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
            }
        }
    }

    private var phoneName: String {
        model.iphoneConnected ? (model.iphoneBridge.deviceHello?.name ?? "iPhone connected") : "iPhone companion"
    }

    private var phoneSubtitle: String {
        model.iphoneConnected ? "\(model.iphoneContacts.count) contacts available" : model.iphoneBridge.statusText
    }
}

private struct MusicSection: View {
    @ObservedObject var model: DashboardViewModel

    var body: some View {
        ZStack(alignment: .bottom) {
            HStack(spacing: 16) {
                MediaSourcePanel(
                    title: "iPad Apple Music",
                    track: model.media.title.isEmpty ? nil : model.media.title,
                    artist: model.media.artist.isEmpty ? nil : model.media.artist,
                    isPlaying: model.media.isPlaying,
                    unavailableMessage: "Nothing is playing on the iPad.",
                    controlsDisabled: false,
                    previous: { model.previousTrack() },
                    toggle: { model.togglePlayback() },
                    next: { model.nextTrack() }
                )
                MediaSourcePanel(
                    title: "iPhone Apple Music",
                    track: model.iphoneMedia.title,
                    artist: model.iphoneMedia.artist,
                    isPlaying: model.iphoneMedia.isPlaying,
                    unavailableMessage: iphoneUnavailableMessage,
                    controlsDisabled: !model.iphoneConnected,
                    previous: { model.previousIPhoneTrack() },
                    toggle: { model.toggleIPhonePlayback() },
                    next: { model.nextIPhoneTrack() }
                )
            }

            Button {
                model.openYouTubeMusic()
            } label: {
                Label("Open YouTube Music on iPad", systemImage: "play.rectangle.fill")
                    .font(.headline)
                    .frame(minHeight: 52)
            }
            .buttonStyle(.bordered)
            .padding(.bottom, 18)
        }
    }

    private var iphoneUnavailableMessage: String {
        model.iphoneConnected
            ? "Nothing is playing in Apple Music on the iPhone."
            : "Connect Kalpana Drive Phone to control Apple Music on the iPhone."
    }
}

private struct MediaSourcePanel: View {
    let title: String
    let track: String?
    let artist: String?
    let isPlaying: Bool
    let unavailableMessage: String
    let controlsDisabled: Bool
    let previous: () -> Void
    let toggle: () -> Void
    let next: () -> Void

    var body: some View {
        DriveCard {
            VStack(spacing: 22) {
                Label(title, systemImage: "music.note").font(.title2.bold())
                Image(systemName: track == nil ? "music.note.slash" : "music.note")
                    .font(.system(size: 70, weight: .bold))
                Text(track ?? "Nothing playing").font(.system(size: 30, weight: .bold)).lineLimit(2)
                Text(artist ?? unavailableMessage)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                HStack(spacing: 24) {
                    MediaControlButton(icon: "backward.end.fill", action: previous)
                    MediaControlButton(icon: isPlaying ? "pause.fill" : "play.fill", action: toggle)
                    MediaControlButton(icon: "forward.end.fill", action: next)
                }
                .disabled(controlsDisabled)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct MediaControlButton: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .bold))
                .frame(width: 78, height: 78)
                .background(Color.primary)
                .foregroundStyle(Color(uiColor: .systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

private struct PhoneSection: View {
    @ObservedObject var model: DashboardViewModel

    var body: some View {
        DriveCard {
            VStack(spacing: 14) {
                PhoneConnectionHeader(model: model)
                pendingConnection
                phoneContent
                manualDial
                Text("Contacts and outgoing call initiation are supported. Incoming cellular calls remain in Apple’s Phone/Continuity interface because public iOS APIs do not allow Kalpana Drive to answer or reject them.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var pendingConnection: some View {
        if let peer = model.iphoneBridge.pendingPeer {
            HStack {
                Text("Allow encrypted connection from \(peer.displayName)?").font(.headline)
                Spacer()
                Button("Reject") { model.rejectIPhoneConnection() }.buttonStyle(.bordered)
                Button("Approve") { model.approveIPhoneConnection() }.buttonStyle(.borderedProminent)
            }
            .padding(14)
            .background(Color.primary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    @ViewBuilder
    private var phoneContent: some View {
        if model.iphoneConnected {
            if model.drivingState.restrictsInteraction {
                Text("Contact browsing and number entry are hidden while moving. Say “Call <name>”.")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .padding()
                Spacer()
            } else {
                ContactBrowser(model: model)
            }
        } else {
            Spacer()
            Image(systemName: "iphone.gen2.radiowaves.left.and.right")
                .font(.system(size: 72, weight: .bold))
            Text("Open Kalpana Drive Phone on your iPhone")
                .font(.system(size: 34, weight: .bold))
            Text("Keep Wi-Fi and Bluetooth enabled, choose this iPad in the iPhone app, then approve the connection here.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 760)
            Spacer()
        }
    }

    @ViewBuilder
    private var manualDial: some View {
        if !model.drivingState.restrictsInteraction {
            HStack(spacing: 10) {
                TextField("Dial number manually", text: $model.phoneNumberToDial)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.phonePad)
                    .font(.title3)
                Button {
                    model.callPhoneNumber()
                } label: {
                    Label("Call", systemImage: "phone.fill")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

private struct PhoneConnectionHeader: View {
    @ObservedObject var model: DashboardViewModel

    var body: some View {
        HStack {
            Image(systemName: model.iphoneConnected ? "iphone.gen2" : "iphone.gen2.slash").font(.title)
            VStack(alignment: .leading) {
                Text(model.iphoneBridge.deviceHello?.name ?? "iPhone companion").font(.title2.bold())
                Text(model.iphoneBridge.statusText).foregroundStyle(.secondary)
            }
            Spacer()
            if let battery = model.iphoneBridge.deviceState?.batteryPercent, model.iphoneConnected {
                Text("\(battery)%").font(.headline)
            }
            if model.iphoneConnected {
                Button("Disconnect") { model.disconnectIPhone() }.buttonStyle(.bordered)
            }
        }
    }
}

private struct ContactBrowser: View {
    @ObservedObject var model: DashboardViewModel

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                TextField("Search iPhone contacts", text: Binding(
                    get: { model.contactQuery },
                    set: { value in model.updateContactQuery(value) }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                Button("Sync") { model.syncIPhone() }.buttonStyle(.bordered)
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(model.filteredIPhoneContacts) { contact in
                        ContactRow(contact: contact) { number in
                            model.call(number: number)
                        }
                    }
                }
            }
        }
    }
}

private struct ContactRow: View {
    let contact: PhoneBridgeContact
    let call: (String) -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "person.crop.circle.fill").font(.system(size: 42))
            VStack(alignment: .leading, spacing: 3) {
                Text(contact.displayName).font(.headline)
                Text(contact.phoneNumbers.joined(separator: " • "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let number = contact.phoneNumbers.first {
                Button {
                    call(number)
                } label: {
                    Image(systemName: "phone.fill").frame(width: 52, height: 52)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct SettingsSection: View {
    @ObservedObject var model: DashboardViewModel

    var body: some View {
        DriveCard {
            VStack(spacing: 24) {
                Image(systemName: "gearshape.fill").font(.system(size: 72, weight: .bold))
                Text("Kalpana Drive Settings").font(.system(size: 38, weight: .bold))
                Picker("Appearance", selection: Binding(
                    get: { model.appearance },
                    set: { value in model.setAppearance(value) }
                )) {
                    Text("Day").tag(DriveAppearance.day)
                    Text("Night").tag(DriveAppearance.night)
                    Text("High sunlight").tag(DriveAppearance.highSunlight)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 620)

                VStack(spacing: 8) {
                    Text("iPhone companion").font(.headline)
                    Text(model.iphoneBridge.statusText).foregroundStyle(.secondary)
                    if model.iphoneConnected {
                        Button("Sync iPhone now") { model.syncIPhone() }.buttonStyle(.bordered)
                    }
                }

                Button("Open System Health") { model.openDiagnostics() }
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
    let content: Content

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
