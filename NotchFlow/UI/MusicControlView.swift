import AppKit
import SwiftUI

struct MusicControlView: View {
    @ObservedObject var music: MusicController

    @State private var seekPosition: Double = 0
    @State private var isSeeking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                MusicArtworkView(data: music.snapshot.artworkData, size: 72)

                VStack(alignment: .leading, spacing: 4) {
                    Text(displayTitle)
                        .font(.title3.bold())
                        .lineLimit(2)
                    Text(displayArtist)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if !music.snapshot.album.isEmpty {
                        Text(music.snapshot.album)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }

            if music.snapshot.duration > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("播放进度", systemImage: "waveform")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text("\(timeText(seekPosition)) / \(timeText(music.snapshot.duration))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: $seekPosition,
                        in: 0...music.snapshot.duration,
                        onEditingChanged: handleSeeking
                    )
                    .tint(.blue)
                    .controlSize(.large)
                    .disabled(!music.snapshot.canSeek)
                    .accessibilityLabel("播放进度")
                }
                .padding(10)
                .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }

            HStack(spacing: 18) {
                Button { music.send(.previous) } label: {
                    Image(systemName: "backward.fill")
                }
                Button { music.send(.playPause) } label: {
                    Image(systemName: music.snapshot.playbackState == .playing
                        ? "pause.circle.fill"
                        : "play.circle.fill")
                        .font(.system(size: 34))
                }
                .buttonStyle(.plain)
                Button { music.send(.next) } label: {
                    Image(systemName: "forward.fill")
                }

                Spacer()

                Button("打开 Apple Music") { music.openSource() }
            }
            .disabled(music.isPerformingCommand)

            Text(music.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .onAppear {
            seekPosition = music.snapshot.position
            music.refresh()
        }
        .onChange(of: music.snapshot.position) { _, newValue in
            if !isSeeking { seekPosition = newValue }
        }
    }

    private var displayTitle: String {
        if !music.snapshot.title.isEmpty { return music.snapshot.title }
        if music.snapshot.running { return "Apple Music 暂无播放内容" }
        return "Apple Music 未运行"
    }

    private var displayArtist: String {
        music.snapshot.artist.isEmpty ? "打开 Apple Music 并播放一首歌" : music.snapshot.artist
    }

    private func handleSeeking(_ editing: Bool) {
        isSeeking = editing
        if !editing {
            music.seek(to: seekPosition)
        }
    }

    private func timeText(_ value: TimeInterval) -> String {
        guard value.isFinite, value >= 0 else { return "0:00" }
        let total = Int(value.rounded(.down))
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}

struct MusicArtworkView: View {
    let data: Data?
    let size: CGFloat

    var body: some View {
        Group {
            if let data, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.accentColor.opacity(0.2)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.36, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
    }
}
