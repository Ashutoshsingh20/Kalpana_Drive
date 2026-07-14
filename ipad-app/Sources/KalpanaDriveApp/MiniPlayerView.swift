import SwiftUI
import UIKit

struct MiniPlayerView: View {
    @ObservedObject var model: DashboardViewModel
    @ObservedObject var nowPlaying: NowPlayingObserver = .shared

    var body: some View {
        if nowPlaying.isActive {
            HStack(spacing: 16) {
                // Artwork
                if let image = nowPlaying.trackArtwork {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
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
                    Text(nowPlaying.trackTitle)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                    if !nowPlaying.trackArtist.isEmpty {
                        Text(nowPlaying.trackArtist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Controls
                HStack(spacing: 18) {
                    Button(action: { nowPlaying.previous() }) {
                        Image(systemName: "backward.fill").font(.subheadline)
                    }
                    .buttonStyle(.plain)

                    Button(action: { nowPlaying.togglePlayPause() }) {
                        Image(systemName: nowPlaying.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)

                    Button(action: { nowPlaying.next() }) {
                        Image(systemName: "forward.fill").font(.subheadline)
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        withAnimation { model.selectSection(.music) }
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
            .backgroundModifier()
            .frame(maxWidth: 420)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        // No fallback banner — if nothing is playing, mini-player is invisible
    }
}

private extension View {
    func backgroundModifier() -> some View {
        self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
