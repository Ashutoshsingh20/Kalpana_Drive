import KalpanaDriveCore
import MapKit
import SwiftUI

struct DashboardView: View {
    @ObservedObject var model: DashboardViewModel

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 900
            ZStack {
                palette.background.ignoresSafeArea()
                VStack(spacing: 16) {
                    statusBar
                    if let error = model.errorMessage {
                        errorBanner(error)
                    }
                    sectionContent(compact: compact)
                    bottomControls
                }
                .padding(20)
            }
        }
        .foregroundStyle(palette.foreground)
        .sheet(isPresented: $model.isDiagnosticsPresented) {
            DiagnosticsView(model: model)
        }
    }

    private var statusBar: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.now, format: .dateTime.hour().minute())
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                Text(model.now, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.headline)
            }
            Spacer()
            statusPill(model.drivingState.rawValue, prominent: model.drivingState.restrictsInteraction)
            statusPill("GPS: \(model.locationAccuracy)")
            statusPill("AUDIO: \(model.audioRoute.rawValue.uppercased())")
            statusPill(model.isOnline ? "ONLINE" : "OFFLINE", prominent: !model.isOnline)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func sectionContent(compact: Bool) -> some View {
        switch model.selectedSection {
        case .home:
            dashboardGrid(compact: compact)
        case .map:
            NavigationMapSection(model: model)
        case .music:
            MusicSection(
                media: model.media,
                previous: model.previousTrack,
                togglePlayback: model.togglePlayback,
                next: model.nextTrack,
                openYouTubeMusic: model.openYouTubeMusic
            )
        case .phone:
            PhoneSection(model: model)
        case .settings:
            SettingsSection(model: model)
        }
    }

    private func dashboardGrid(compact: Bool) -> some View {
        HStack(spacing: 16) {
            LiveMapCard(speedKPH: model.speedKPH, expanded: false, route: model.mapRoute)
                .frame(maxWidth: .infinity)
            VStack(spacing: 16) {
                NavigationCard(route: model.activeRoute)
                MediaCard(media: model.media, togglePlayback: model.togglePlayback)
                PhoneCard()
            }
            .frame(width: compact ? 300 : 360)
        }
        .frame(maxHeight: .infinity)
    }

    private var bottomControls: some View {
        HStack(spacing: 12) {
            ForEach(DashboardSection.allCases) { section in
                Button {
                    model.selectSection(section)
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: sectionIcon(section))
                        Text(section.rawValue)
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(model.selectedSection == section ? palette.foreground : palette.card)
                    .foregroundStyle(model.selectedSection == section ? palette.background : palette.foreground)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Open \(section.rawValue)")
            }

            Button(action: model.activateVoice) {
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
            .accessibilityLabel(model.isVoiceActive ? "Stop listening" : "Talk to Kalpana")
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message)
                .font(.headline)
                .lineLimit(2)
            Spacer()
            Button("Dismiss", action: model.clearError)
                .buttonStyle(.bordered)
        }
        .padding(14)
        .background(palette.card)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(palette.foreground, lineWidth: 2))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func statusPill(_ text: String, prominent: Bool = false) -> some View {
        Text(text)
            .font(.caption.bold())
            .padding(.horizontal, 13)
            .frame(minHeight: 42)
            .background(prominent ? palette.foreground : palette.card)
            .foregroundStyle(prominent ? palette.background : palette.foreground)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.border, lineWidth: 2))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func sectionIcon(_ section: DashboardSection) -> String {
        switch section {
        case .home: "house.fill"
        case .map: "map.fill"
        case .music: "music.note"
        case .phone: "phone.fill"
        case .settings: "gearshape.fill"
        }
    }

    private var palette: DrivePalette { DrivePalette(appearance: model.appearance) }
}

private struct LiveMapCard: View {
    let speedKPH: Int
    let expanded: Bool
    let route: MKRoute?
    @State private var position: MapCameraPosition = .userLocation(followsHeading: true, fallback: .automatic)

    var body: some View {
        DriveCard(insets: 0) {
            ZStack(alignment: .topLeading) {
                Map(position: $position) {
                    UserAnnotation()
                    if let route {
                        MapPolyline(route.polyline)
                            .stroke(.primary, lineWidth: 7)
                    }
                }
                .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
                .mapControls {
                    MapCompass()
                    MapScaleView()
                    MapUserLocationButton()
                }

                HStack(alignment: .top, spacing: 12) {
                    Label("LIVE MAP", systemImage: "location.fill")
                        .font(.headline)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 46)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Spacer()
                    VStack(spacing: 0) {
                        Text("\(speedKPH)")
                            .font(.system(size: expanded ? 58 : 48, weight: .black, design: .rounded))
                        Text("KM/H")
                            .font(.caption.bold())
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
                Map(position: $position) {
                    UserAnnotation()
                    if let route = model.mapRoute {
                        MapPolyline(route.polyline)
                            .stroke(.primary, lineWidth: 8)
                    }
                    ForEach(Array(model.alternativeRoutes.enumerated()), id: \.offset) { _, alternative in
                        MapPolyline(alternative.polyline)
                            .stroke(.secondary.opacity(0.65), lineWidth: 4)
                    }
                }
                .mapStyle(.standard(elevation: .realistic))
                .mapControls {
                    MapCompass()
                    MapScaleView()
                    MapUserLocationButton()
                }

                VStack(spacing: 10) {
                    if !model.drivingState.restrictsInteraction {
                        HStack(spacing: 10) {
                            TextField("Search a place or address", text: $model.destinationQuery)
                                .textFieldStyle(.plain)
                                .font(.title3.bold())
                                .submitLabel(.search)
                                .onSubmit(model.searchDestinations)
                            Button(action: model.searchDestinations) {
                                if model.isSearching {
                                    ProgressView().frame(width: 54, height: 54)
                                } else {
                                    Image(systemName: "magnifyingglass")
                                        .font(.title2.bold())
                                        .frame(width: 54, height: 54)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.horizontal, 16)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                        if !model.searchResults.isEmpty {
                            VStack(spacing: 0) {
                                ForEach(model.searchResults.prefix(5)) { result in
                                    Button { model.startNavigation(to: result) } label: {
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
                                    if result.id != model.searchResults.prefix(5).last?.id { Divider() }
                                }
                            }
                            .padding(.horizontal, 16)
                            .background(.regularMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    } else {
                        Text("Destination typing is unavailable while driving. Use Kalpana voice control.")
                            .font(.headline)
                            .padding(14)
                            .background(.regularMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    Spacer()

                    if let route = model.activeRoute {
                        HStack(spacing: 18) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(route.nextInstruction).font(.title2.bold()).lineLimit(2)
                                Text("\(distance(route.distanceRemainingMetres)) • ETA \(route.expectedArrival.formatted(date: .omitted, time: .shortened))")
                                    .font(.headline)
                            }
                            Spacer()
                            Button("Cancel Route", action: model.cancelNavigation)
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                        }
                        .padding(16)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(14)
            }
        }
    }

    private func distance(_ metres: Double) -> String {
        if metres >= 1_000 { return String(format: "%.1f km", metres / 1_000) }
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
                    Text(route.nextInstruction)
                        .font(.title2.bold())
                        .lineLimit(2)
                    HStack {
                        Text(route.destination.name)
                        Spacer()
                        Text(route.expectedArrival, format: .dateTime.hour().minute())
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                } else {
                    Text("No active route")
                        .font(.title2.bold())
                    Text("Open Map and select a real destination to begin navigation.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct MediaCard: View {
    let media: MediaSnapshot
    let togglePlayback: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        DriveCard {
            HStack(spacing: 16) {
                Image(systemName: media.title.isEmpty ? "music.note.slash" : "music.note")
                    .font(.system(size: 34, weight: .bold))
                    .frame(width: 64, height: 64)
                    .background(Color.primary.opacity(0.12))
                VStack(alignment: .leading, spacing: 4) {
                    Text(media.title.isEmpty ? "Nothing playing" : media.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(media.title.isEmpty ? "Start playback in Apple Music" : media.artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button(action: togglePlayback) {
                    Image(systemName: media.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2.bold())
                        .frame(width: 64, height: 64)
                        .background(Color.primary)
                        .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct PhoneCard: View {
    var body: some View {
        DriveCard {
            HStack {
                Image(systemName: "phone.fill")
                    .font(.title)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Phone Dialler")
                        .font(.headline)
                    Text("Ready to dial directly from iPad.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }
}

private struct MusicSection: View {
    let media: MediaSnapshot
    let previous: () -> Void
    let togglePlayback: () -> Void
    let next: () -> Void
    let openYouTubeMusic: () -> Void

    var body: some View {
        DriveCard {
            VStack(spacing: 28) {
                Image(systemName: media.title.isEmpty ? "music.note.slash" : "music.note")
                    .font(.system(size: 86, weight: .bold))
                Text(media.title.isEmpty ? "Nothing playing" : media.title)
                    .font(.system(size: 38, weight: .bold))
                Text(media.title.isEmpty ? "Start playback in Apple Music on this iPad." : media.artist)
                    .font(.title2)
                    .foregroundStyle(.secondary)
                HStack(spacing: 28) {
                    mediaButton("backward.end.fill", action: previous)
                    mediaButton(media.isPlaying ? "pause.fill" : "play.fill", action: togglePlayback)
                    mediaButton("forward.end.fill", action: next)
                }
                Button(action: openYouTubeMusic) {
                    Label("Open YouTube Music", systemImage: "play.rectangle.fill")
                        .font(.title3.bold())
                        .frame(minWidth: 280, minHeight: 60)
                }
                .buttonStyle(.borderedProminent)
                Text("iPadOS does not allow Kalpana Drive to read or control another app's YouTube Music session. Playback controls above operate the public Apple Music system player; YouTube Music opens in its own app or website.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 680)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func mediaButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 38, weight: .bold))
                .frame(width: 86, height: 86)
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
            VStack(spacing: 22) {
                Image(systemName: "phone.circle.fill")
                    .font(.system(size: 76, weight: .bold))
                Text("Dial a Number")
                    .font(.system(size: 36, weight: .bold))
                Text("Enter a number to call using your iPad's cellular plan, or Wi-Fi calling via Continuity.")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 760)

                HStack(spacing: 12) {
                    TextField("Phone number", text: $model.phoneNumberToDial)
                        .textFieldStyle(.roundedBorder)
                        .font(.title2)
                        .frame(width: 300)
                        .keyboardType(.phonePad)

                    Button(action: model.callPhoneNumber) {
                        Image(systemName: "phone.fill")
                            .font(.title2.bold())
                            .frame(width: 60, height: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
                .padding(.top, 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct SettingsSection: View {
    @ObservedObject var model: DashboardViewModel

    var body: some View {
        DriveCard {
            VStack(spacing: 24) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 72, weight: .bold))
                Text("Kalpana Drive Settings")
                    .font(.system(size: 38, weight: .bold))
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

private struct DrivePalette {
    let appearance: DriveAppearance
    var background: Color { appearance == .day ? .white : .black }
    var foreground: Color { appearance == .day ? .black : .white }
    var card: Color { appearance == .day ? Color(white: 0.92) : Color(white: 0.10) }
    var border: Color { foreground.opacity(0.75) }
}
