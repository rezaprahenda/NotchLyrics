import SwiftUI
import AppKit

// MARK: - Pilih lirik manual

struct LyricsPickerView: View {
    @ObservedObject var lyrics: LyricsStore
    let trackDuration: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(L("Pilih lirik", "Choose lyrics"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                if lyrics.hasOverride {
                    Button(L("Kembali ke otomatis", "Back to automatic")) { lyrics.resetToAutomatic() }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Button {
                    lyrics.isPickerOpen = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if lyrics.isSearchingCandidates {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if lyrics.candidates.isEmpty {
                Text(L("Tidak ada hasil lain di LRCLIB", "No other results on LRCLIB"))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(lyrics.candidates) { c in
                            CandidateRow(candidate: c, trackDuration: trackDuration) {
                                lyrics.choose(c)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct CandidateRow: View {
    let candidate: LyricCandidate
    let trackDuration: Double
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(candidate.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(candidate.album.isEmpty ? candidate.artist : "\(candidate.artist) · \(candidate.album)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                // Durasi hijau = cocok dengan lagu yang sedang diputar (selisih ≤ 2 detik).
                Text(format(candidate.duration))
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(durationMatches ? Color.green.opacity(0.85) : Color.white.opacity(0.45))
                Text(candidate.hasSynced ? L("Sinkron", "Synced") : (candidate.instrumental ? "Instrumental" : L("Teks", "Text")))
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(candidate.hasSynced ? 0.95 : 0.6))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(candidate.hasSynced ? 0.18 : 0.08)))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(hover ? 0.1 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }

    private var durationMatches: Bool {
        trackDuration > 0 && abs(candidate.duration - trackDuration) <= 2
    }

    private func format(_ t: Double) -> String {
        let s = Int(max(t, 0))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

struct SyncedLyricsView: View {
    let lines: [LyricLine]
    @ObservedObject var player: PlayerMonitor
    @ObservedObject var lyrics: LyricsStore
    @State private var current: Int = -1
    @State private var hovered: Int?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    Color.clear.frame(height: 30)
                    ForEach(lines) { line in
                        let isCurrent = line.id == current
                        let isHovered = line.id == hovered
                        // Klik baris lirik = lompat ke bagian lagu itu.
                        Button {
                            player.seek(to: line.time - lyrics.offset)
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                let font = Font.system(size: isCurrent ? 16 : 13.5,
                                                       weight: isCurrent ? .bold : .medium,
                                                       design: .rounded)
                                if isCurrent && lyrics.karaokeEnabled && !line.text.isEmpty {
                                    TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !player.isPlaying)) { _ in
                                        KaraokeText(text: line.text,
                                                    progress: lyrics.lineProgress(in: lines, index: line.id,
                                                                                  position: player.position),
                                                    font: font,
                                                    color: .white)
                                    }
                                } else {
                                    Text(line.text.isEmpty ? "♪" : line.text)
                                        .font(font)
                                        .foregroundStyle(.white.opacity(isCurrent || isHovered ? 1 : (line.id < current ? 0.35 : 0.5)))
                                }
                                if lyrics.romanizationEnabled, let latin = lyrics.romanized[line.id] {
                                    Text(latin)
                                        .font(.system(size: isCurrent ? 13 : 12, weight: .medium, design: .rounded))
                                        .italic()
                                        .foregroundStyle(.white.opacity(isCurrent ? 0.85 : 0.4))
                                }
                                if lyrics.translationEnabled, let translated = lyrics.translations[line.id] {
                                    Text(translated)
                                        .font(.system(size: isCurrent ? 12.5 : 11.5, design: .rounded))
                                        .foregroundStyle(.white.opacity(isCurrent ? 0.7 : 0.3))
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .onHover { inside in
                            if inside {
                                hovered = line.id
                            } else if hovered == line.id {
                                hovered = nil
                            }
                        }
                        .id(line.id)
                    }
                    Color.clear.frame(height: 30)
                }
            }
            .mask(
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.18),
                    .init(color: .black, location: 0.82),
                    .init(color: .clear, location: 1),
                ], startPoint: .top, endPoint: .bottom)
            )
            .task(id: lines) {
                current = -1
                tick(proxy, animated: false)
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    tick(proxy, animated: true)
                }
            }
        }
    }

    private func tick(_ proxy: ScrollViewProxy, animated: Bool) {
        let idx = lyrics.currentIndex(in: lines, position: player.position) ?? -1
        guard idx != current else { return }
        if animated {
            withAnimation(.easeInOut(duration: 0.35)) {
                current = idx
                if idx >= 0 { proxy.scrollTo(idx, anchor: .center) }
            }
        } else {
            current = idx
            if idx >= 0 { proxy.scrollTo(idx, anchor: .center) }
        }
    }
}
