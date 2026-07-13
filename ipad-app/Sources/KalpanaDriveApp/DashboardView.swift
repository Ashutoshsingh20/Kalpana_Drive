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
    @State private var showParkingSheet = false
    @State private var showSavedPlaces = false
    @State private var showTripHistory = false

    var body: some View {
        ZStack(alignment: .top) {
            // Full-bleed live map
            mapView

            // Overlaid controls (search, nav strip, action bar)
            VStack(spacing: 0) {
                searchOverlay
                Spacer()
                if let _ = model.activeRoute {
                    navStrip
                }
                actionBar
            }
            .padding(14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.8), lineWidth: 2))
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
        .sheet(isPresented: $showTripHistory) {
            TripHistorySheet(model: model)
        }
    }

    // MARK: Map
    @ViewBuilder private var mapView: some View {
        Map(position: $position) {
            UserAnnotation()
            // Active route polyline
            if let route = model.mapRoute {
                MapPolyline(route.polyline)
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
            }
            // Alternative route polylines
            ForEach(Array(model.alternativeRoutes.enumerated()), id: \.offset) { item in
                MapPolyline(item.element.polyline)
                    .stroke(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
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
        .mapStyle(currentMapStyle)
        .mapControls {
            MapCompass()
            MapScaleView()
            MapUserLocationButton()
        }
        .ignoresSafeArea()
    }

    private var currentMapStyle: MapStyle {
        switch model.mapStyle {
        case .standard:
            return .standard(elevation: .realistic, pointsOfInterest: .all)
        case .satellite:
            return .imagery(elevation: .realistic)
        case .hybrid:
            return .hybrid(elevation: .realistic, pointsOfInterest: .all)
        }
    }

    // MARK: Search Overlay
    @ViewBuilder private var searchOverlay: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                // Search bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search destination, landmark, or address", text: $model.destinationQuery)
                        .textFieldStyle(.plain)
                        .font(.headline)
                        .submitLabel(.search)
                        .onSubmit { model.searchDestinations() }
                    if !model.destinationQuery.isEmpty {
                        Button(action: {
                            model.destinationQuery = ""
                        }) {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }.buttonStyle(.plain)
                    }
                    Button {
                        model.searchDestinations()
                    } label: {
                        Group {
                            if model.isSearching {
                                ProgressView().tint(.primary)
                            } else {
                                Image(systemName: "magnifyingglass").font(.title3.bold())
                            }
                        }
                        .frame(width: 42, height: 42)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.destinationQuery.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                // Map style toggle
                Menu {
                    ForEach(DriveMapStyle.allCases) { style in
                        Button(action: { model.mapStyle = style }) {
                            Label(style.rawValue, systemImage: style.icon)
                        }
                    }
                } label: {
                    Image(systemName: "map")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }

            // Autocomplete dropdown
            if !model.searchSuggestions.isEmpty && !model.destinationQuery.isEmpty {
                VStack(spacing: 0) {
                    ForEach(model.searchSuggestions.prefix(5), id: \.self) { suggestion in
                        Button {
                            model.destinationQuery = suggestion
                            model.searchDestinations()
                        } label: {
                            HStack {
                                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).frame(width: 24)
                                Text(suggestion).font(.subheadline).lineLimit(1)
                                Spacer()
                            }
                            .frame(minHeight: 46)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
                .padding(.horizontal, 12)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            // Search results
            if !model.searchResults.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(model.searchResults.prefix(8))) { result in
                        Button {
                            model.startNavigation(to: result)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "mappin.circle.fill").foregroundStyle(.blue).font(.title3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.name).font(.headline).lineLimit(1)
                                    Text(result.address).font(.caption).lineLimit(1).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill").foregroundStyle(.secondary)
                            }
                            .frame(minHeight: 58)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
                .padding(.horizontal, 14)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            // Saved place shortcuts (visible when search is empty)
            if model.destinationQuery.isEmpty && model.searchResults.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.savedPlaces.prefix(6)) { place in
                            Button {
                                model.startNavigation(to: Destination(
                                    name: place.name,
                                    address: place.address,
                                    coordinate: place.coordinate,
                                    kind: .favourite
                                ))
                            } label: {
                                Label(place.name, systemImage: savedPlaceIcon(place.label))
                                    .font(.subheadline.bold())
                                    .padding(.horizontal, 12)
                                    .frame(height: 38)
                                    .background(.regularMaterial)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                        if !model.recentDestinations.isEmpty {
                            ForEach(model.recentDestinations.prefix(3)) { dest in
                                Button {
                                    model.startNavigation(to: dest)
                                } label: {
                                    Label(dest.name, systemImage: "clock")
                                        .font(.subheadline)
                                        .padding(.horizontal, 12)
                                        .frame(height: 38)
                                        .background(.regularMaterial)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Nav Strip
    @ViewBuilder private var navStrip: some View {
        if let _ = model.activeRoute {
            VStack(spacing: 8) {
                // Off-route warning
                if model.navIsOffRoute {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text("Off route — recalculating…").font(.headline.bold())
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // Main nav strip
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        if !model.navNextInstruction.isEmpty {
                            Text(model.navNextInstruction)
                                .font(.title2.bold())
                                .lineLimit(2)
                        } else {
                            Text(model.activeRoute?.nextInstruction ?? "")
                                .font(.title2.bold())
                                .lineLimit(2)
                        }
                        HStack(spacing: 12) {
                            Label(distanceString(model.navDistanceRemaining > 0 ? model.navDistanceRemaining : (model.activeRoute?.distanceRemainingMetres ?? 0)), systemImage: "road.lanes")
                            Label("ETA \((model.navETA > Date.distantPast ? model.navETA : (model.activeRoute?.expectedArrival ?? Date())).formatted(date: .omitted, time: .shortened))", systemImage: "clock")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    // Progress ring
                    ZStack {
                        Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 5)
                        Circle()
                            .trim(from: 0, to: CGFloat(model.navProgressPercent / 100))
                            .stroke(Color.blue, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(Int(model.navProgressPercent))%")
                            .font(.caption2.bold())
                    }
                    .frame(width: 52, height: 52)

                    Button("Cancel") { model.cancelNavigation() }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.regular)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                // Alternative routes strip
                if !model.alternativeRoutes.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Text("Alternatives:").font(.caption.bold()).foregroundStyle(.secondary)
                            ForEach(Array(model.alternativeRoutes.prefix(3).enumerated()), id: \.offset) { i, route in
                                Button {
                                    model.selectAlternativeRoute(route)
                                } label: {
                                    VStack(spacing: 2) {
                                        Text(distanceString(route.distance)).font(.caption.bold())
                                        Text(durationString(route.expectedTravelTime)).font(.caption2).foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 12)
                                    .frame(height: 40)
                                    .background(.regularMaterial)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Action Bar
    private var actionBar: some View {
        HStack(spacing: 10) {
            // Trip recording
            Button {
                if model.isTripRecording {
                    model.stopTripRecording()
                } else {
                    model.startTripRecording()
                }
            } label: {
                Label(
                    model.isTripRecording ? "Stop Trip" : "Record Trip",
                    systemImage: model.isTripRecording ? "stop.circle.fill" : "record.circle"
                )
                .font(.subheadline.bold())
                .padding(.horizontal, 14)
                .frame(height: 42)
                .background(model.isTripRecording ? Color.red.opacity(0.85) : Color.primary.opacity(0.12))
                .foregroundColor(model.isTripRecording ? .white : .primary)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            // Trip history
            Button {
                showTripHistory = true
            } label: {
                Label("Trips (\(model.trips.count))", systemImage: "list.bullet.rectangle")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 14)
                    .frame(height: 42)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            Spacer()

            // Parking
            if let _ = model.parkedLocation {
                Button {
                    model.navigateToParking()
                } label: {
                    Label("Navigate to Car", systemImage: "car.fill")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 14)
                        .frame(height: 42)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                Button {
                    model.clearParking()
                } label: {
                    Image(systemName: "car.badge.minus")
                        .font(.headline)
                        .frame(width: 42, height: 42)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    showParkingSheet = true
                } label: {
                    Label("Save Parking", systemImage: "car.badge.plus")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 14)
                        .frame(height: 42)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }

            // Saved places panel
            Button {
                showSavedPlaces = true
            } label: {
                Label("Saved", systemImage: "bookmark.fill")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 14)
                    .frame(height: 42)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
    }

    private func distanceString(_ metres: Double) -> String {
        if metres >= 1_000 { return String(format: "%.1f km", metres / 1_000) }
        return "\(Int(metres.rounded())) m"
    }

    private func durationString(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60)h \(minutes % 60)m"
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

                    // Siri
                    settingsGroup(title: "Siri Commands", icon: "waveform.circle") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("• "Open YouTube Music in Kalpana Drive"")
                            Text("• "Open the map in Kalpana Drive"")
                            Text("• "Search for India Gate in Kalpana Drive"")
                            Text("Activate Siri by voice or the iPad's top button. Siri appears as a system overlay.")
                                .font(.caption).foregroundStyle(.secondary)
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
