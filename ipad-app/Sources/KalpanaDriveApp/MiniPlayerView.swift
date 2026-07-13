import SwiftUI

struct MiniPlayerView: View {
    @ObservedObject var model: DashboardViewModel
    @ObservedObject var browser: YouTubeMusicBrowserController

    var body: some View {
        if browser.isPlayerAvailable && !browser.trackTitle.isEmpty {
            HStack(spacing: 16) {
                // Artwork
                if let url = URL(string: browser.trackArtwork), !browser.trackArtwork.isEmpty {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Image(systemName: "music.note")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)
                            .frame(width: 54, height: 54)
                            .background(Color.primary.opacity(0.1))
                    }
                    .frame(width: 54, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(radius: 4)
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                        .frame(width: 54, height: 54)
                        .background(Color.primary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // Title / Artist
                VStack(alignment: .leading, spacing: 4) {
                    Text(browser.trackTitle)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                    Text(browser.trackArtist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Controls
                HStack(spacing: 14) {
                    Button(action: { browser.previous() }) {
                        Image(systemName: "backward.fill")
                            .font(.subheadline)
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        if browser.isPlaying {
                            browser.pause()
                        } else {
                            browser.play()
                        }
                    }) {
                        Image(systemName: browser.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)

                    Button(action: { browser.next() }) {
                        Image(systemName: "forward.fill")
                            .font(.subheadline)
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        withAnimation {
                            model.selectSection(.music)
                        }
                    }) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.trailing, 8)
            }
            .padding(12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
            .frame(maxWidth: 420)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            // Web player controls unavailable
            HStack(spacing: 12) {
                Image(systemName: "play.rectangle.fill")
                    .foregroundStyle(.secondary)
                Text("Web player controls unavailable")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Open Music") {
                    model.selectSection(.music)
                }
                .font(.caption2.bold())
                .buttonStyle(.bordered)
            }
            .padding(12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
            .frame(maxWidth: 420)
        }
    }
}
