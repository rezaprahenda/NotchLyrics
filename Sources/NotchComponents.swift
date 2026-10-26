import SwiftUI
import AppKit

// MARK: - Komponen kecil

/// Tombol − / + untuk menggeser waktu lirik. Klik angkanya untuk reset.
struct OffsetControl: View {
    @ObservedObject var lyrics: LyricsStore

    var body: some View {
        HStack(spacing: 2) {
            SmallIconButton(symbol: "minus") { lyrics.adjustOffset(by: -0.5) }
            Button {
                lyrics.resetOffset()
            } label: {
                Text(label)
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(lyrics.offset == 0 ? 0.45 : 0.95))
                    .frame(minWidth: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            SmallIconButton(symbol: "plus") { lyrics.adjustOffset(by: 0.5) }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.white.opacity(0.08)))
        .help(L("+ = lirik lebih cepat, − = lebih lambat. Klik angka untuk reset.", "+ = lyrics earlier, − = later. Click the number to reset."))
    }

    private var label: String {
        lyrics.offset == 0 ? "0.0s" : String(format: "%+.1fs", lyrics.offset)
    }
}

struct SmallIconButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ControlsView: View {
    @ObservedObject var player: PlayerMonitor

    var body: some View {
        HStack(spacing: 6) {
            // Tombol favorit hanya muncul untuk Apple Music.
            if let fav = player.isFavorite {
                ControlButton(symbol: fav ? "heart.fill" : "heart", size: 13,
                              tint: fav ? Color(red: 0.98, green: 0.24, blue: 0.35) : .white,
                              box: 26) {
                    player.toggleFavorite()
                }
            }
            if let shuffle = player.shuffle {
                ControlButton(symbol: "shuffle", size: 12,
                              tint: .white.opacity(shuffle ? 1 : 0.35), box: 26) {
                    player.toggleShuffle()
                }
            }
            ControlButton(symbol: "backward.fill", size: 14) { player.previous() }
            ControlButton(symbol: player.isPlaying ? "pause.fill" : "play.fill", size: 20) { player.playPause() }
            ControlButton(symbol: "forward.fill", size: 14) { player.next() }
            if let mode = player.repeatMode {
                ControlButton(symbol: mode == .one ? "repeat.1" : "repeat", size: 12,
                              tint: .white.opacity(mode == .off ? 0.35 : 1), box: 26) {
                    player.cycleRepeat()
                }
            }
        }
    }
}

struct ControlButton: View {
    let symbol: String
    let size: CGFloat
    var tint: Color = .white
    var box: CGFloat = 32
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: box, height: box)
                .background(Circle().fill(Color.white.opacity(hover ? 0.12 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Progress bar yang bisa diklik / di-drag untuk lompat ke bagian lagu.
struct ProgressBar: View {
    @ObservedObject var player: PlayerMonitor
    let duration: Double
    @State private var dragFraction: Double?
    @State private var hovering = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let pos = dragFraction.map { $0 * duration } ?? player.position
            let fraction = duration > 0 ? min(max(pos / duration, 0), 1) : 0
            let active = hovering || dragFraction != nil
            HStack(spacing: 8) {
                Text(format(pos)).monospacedDigit()
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.2))
                            .frame(height: active ? 6 : 4)
                        Capsule()
                            .fill(Color.white.opacity(active ? 1 : 0.85))
                            .frame(width: g.size.width * fraction, height: active ? 6 : 4)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                dragFraction = min(max(v.location.x / max(g.size.width, 1), 0), 1)
                            }
                            .onEnded { v in
                                let f = min(max(v.location.x / max(g.size.width, 1), 0), 1)
                                dragFraction = nil
                                if duration > 0 { player.seek(to: f * duration) }
                            }
                    )
                }
                .frame(height: 14)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.15), value: active)
                Text(format(duration)).monospacedDigit()
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white.opacity(0.6))
        }
        .frame(height: 16)
    }

    private func format(_ t: Double) -> String {
        let s = Int(max(t, 0))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// "🌙 23 mnt" di samping nama app saat sleep timer aktif.
struct SleepIndicator: View {
    @ObservedObject var player: PlayerMonitor

    var body: some View {
        if player.sleepAtTrackEnd || player.sleepUntil != nil {
            TimelineView(.periodic(from: .now, by: 15)) { ctx in
                HStack(spacing: 3) {
                    Image(systemName: "moon.fill").font(.system(size: 8))
                    Text(label(now: ctx.date)).font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    private func label(now: Date) -> String {
        if player.sleepAtTrackEnd { return L("akhir lagu", "end of song") }
        guard let until = player.sleepUntil else { return "" }
        let minutes = max(1, Int((until.timeIntervalSince(now) / 60).rounded(.up)))
        return L("\(minutes) mnt", "\(minutes) min")
    }
}

/// Volume app musik (Spotify/Music), bukan volume sistem.
struct VolumeControl: View {
    @ObservedObject var player: PlayerMonitor

    var body: some View {
        if let v = player.volume {
            HStack(spacing: 4) {
                Image(systemName: v < 1 ? "speaker.slash.fill" : (v < 50 ? "speaker.wave.1.fill" : "speaker.wave.2.fill"))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 16)
                Slider(value: Binding(get: { player.volume ?? 0 },
                                      set: { player.setVolume($0) }),
                       in: 0...100)
                    .controlSize(.mini)
                    .tint(.white)
            }
            .frame(width: 96)
        }
    }
}

struct ArtworkView: View {
    let image: NSImage?
    let size: CGFloat
    let corner: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.white.opacity(0.12)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.45))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        // Garis tepi tipis: bentuk cover tetap terlihat walau gambarnya berpinggiran hitam.
        .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous)
            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
    }
}

struct EqualizerView: View {
    let isPlaying: Bool
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Reduce Motion: batang diam (tinggi tetap), tanpa animasi.
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isPlaying || reduceMotion)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2.5) {
                ForEach(0..<4, id: \.self) { i in
                    let phase = t * (4.2 + Double(i) * 1.3) + Double(i) * 1.7
                    let h = reduceMotion ? (isPlaying ? [0.5, 0.9, 0.65, 0.8][i] : 0.25)
                        : (isPlaying ? 0.35 + 0.65 * abs(sin(phase)) : 0.25)
                    Capsule()
                        .fill(color.opacity(0.9))
                        .frame(width: 2.6, height: 14 * h)
                }
            }
            .frame(height: 14)
        }
    }
}

struct EmptyStateView: View {
    let permissionDenied: MusicSource?
    let error: String?

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: permissionDenied == nil ? "music.note" : "lock.fill")
                .font(.system(size: 22))
                .foregroundStyle(.white.opacity(0.6))
            if let src = permissionDenied {
                Text(L("Izin dibutuhkan untuk membaca \(src.displayName)", "Permission needed to read \(src.displayName)"))
                    .font(.system(size: 13, weight: .semibold))
                Text(L("Buka System Settings › Privacy & Security › Automation, lalu aktifkan \(src.displayName) untuk popocu.", "Open System Settings › Privacy & Security › Automation and enable \(src.displayName) for popocu."))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            } else {
                Text(L("Tidak ada musik yang diputar", "Nothing playing"))
                    .font(.system(size: 13, weight: .semibold))
                Text(L("Putar lagu di Spotify atau Apple Music", "Play a song in Spotify or Apple Music"))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
            }
            if let error, permissionDenied == nil {
                Text(error)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.orange.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .textSelection(.enabled)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
