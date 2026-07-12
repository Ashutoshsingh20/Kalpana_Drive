import SwiftUI
import KalpanaDriveCore

struct DashboardView: View {
    @ObservedObject var model: DashboardViewModel

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 900
            ZStack {
                palette.background.ignoresSafeArea()
                VStack(spacing: 16) {
                    statusBar
                    if model.selectedSection == .home {
                        dashboardGrid(compact: compact)
                    } else {
                        sectionPlaceholder
                    }
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
            statusPill("AUDIO: \(model.audioRoute.rawValue.uppercased())")
            statusPill("PHONE: \(model.phone.state.rawValue.uppercased())")
        }
        .accessibilityElement(children: .combine)
    }

    private func dashboardGrid(compact: Bool) -> some View {
        HStack(spacing: 16) {
            PlaceholderMapCard(speedKPH: model.speedKPH, isMoving: model.drivingState == .moving)
                .frame(maxWidth: .infinity)
            VStack(spacing: 16) {
                NavigationCard()
                MediaCard(media: model.media, togglePlayback: model.togglePlayback)
                PhoneCard(phone: model.phone)
            }
            .frame(width: compact ? 300 : 360)
        }
        .frame(maxHeight: .infinity)
    }

    private var sectionPlaceholder: some View {
        DriveCard {
            VStack(spacing: 18) {
                Image(systemName: sectionIcon(model.selectedSection))
                    .font(.system(size: 62, weight: .bold))
                Text(model.selectedSection.rawValue)
                    .font(.system(size: 40, weight: .bold))
                Text(model.drivingState.restrictsInteraction ? "Detailed controls are unavailable while moving." : "This Phase 1 section is ready for provider integration.")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                if model.selectedSection == .settings {
                    Button("Open System Health") { model.isDiagnosticsPresented = true }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(model.drivingState.restrictsInteraction)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var bottomControls: some View {
        HStack(spacing: 12) {
            ForEach(DashboardSection.allCases) { section in
                Button {
                    model.selectedSection = section
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
                    Text("Kalpana")
                }
                .font(.headline)
                .frame(width: 128, height: 64)
                .background(palette.foreground)
                .foregroundStyle(palette.background)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Talk to Kalpana")
        }
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

private struct PlaceholderMapCard: View {
    let speedKPH: Int
    let isMoving: Bool

    var body: some View {
        DriveCard {
            ZStack {
                Canvas { context, size in
                    let color = Color.primary.opacity(0.18)
                    for offset in stride(from: -size.height, through: size.width, by: 90) {
                        var path = Path()
                        path.move(to: CGPoint(x: offset, y: 0))
                        path.addLine(to: CGPoint(x: offset + size.height, y: size.height))
                        context.stroke(path, with: .color(color), lineWidth: 3)
                    }
                }
                VStack {
                    HStack {
                        Label("MAP PREVIEW", systemImage: "location.fill")
                            .font(.headline)
                        Spacer()
                        Text("SIMULATED")
                            .font(.caption.bold())
                    }
                    Spacer()
                    Text("\(speedKPH)")
                        .font(.system(size: 112, weight: .black, design: .rounded))
                    Text("KM/H • GPS")
                        .font(.title2.bold())
                    Spacer()
                    Text(isMoving ? "Moving simulation active" : "Parked simulation active")
                        .font(.headline)
                }
                .padding(22)
            }
        }
    }
}

private struct NavigationCard: View {
    var body: some View {
        DriveCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("NAVIGATION", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.headline)
                Text("No active route")
                    .font(.title2.bold())
                Text("Home • College • Work")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
                Image(systemName: "music.note")
                    .font(.system(size: 34, weight: .bold))
                    .frame(width: 64, height: 64)
                    .background(Color.primary.opacity(0.12))
                VStack(alignment: .leading, spacing: 4) {
                    Text(media.title).font(.headline).lineLimit(1)
                    Text(media.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    Text("SIMULATED MEDIA").font(.caption2.bold())
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
    let phone: PhoneConnectionSnapshot
    var body: some View {
        DriveCard {
            HStack {
                Image(systemName: "iphone.gen2.slash").font(.title)
                VStack(alignment: .leading) {
                    Text("Phone disconnected").font(.headline)
                    Text("Companion pairing begins in Phase 2").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }
}

struct DriveCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
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
