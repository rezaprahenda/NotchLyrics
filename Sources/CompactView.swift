import SwiftUI
import AppKit

// MARK: - Compact

struct CompactView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var player: PlayerMonitor
    @ObservedObject var lyrics: LyricsStore
    let showLine: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ArtworkView(image: player.artwork, size: 20, corner: 5)
                Spacer(minLength: vm.baseWidth)
                EqualizerView(isPlaying: player.isPlaying,
                              color: vm.accent(for: player))
                    .frame(width: 20, height: 14)
            }
            .padding(.horizontal, 14)
            .frame(height: vm.notchSize.height)

            if showLine, let lines = lyrics.state.syncedLines {
                // Berhenti berdetak saat musik di-pause, supaya tidak memakan CPU.
                // Karaoke butuh gerakan halus, jadi detaknya lebih rapat.
                TimelineView(.animation(minimumInterval: lyrics.karaokeEnabled ? 1.0 / 30 : 0.1,
                                        paused: !player.isPlaying)) { _ in
                    let idx = lyrics.currentIndex(in: lines, position: player.position)
                    let original = idx.map { lines[$0].text } ?? ""
                    let texts: (primary: String, secondary: String?) = idx.map {
                        lyrics.compactText(id: lines[$0].id, original: original)
                    } ?? (primary: original, secondary: nil)
                    let progress: Double? = (lyrics.karaokeEnabled && !texts.primary.isEmpty)
                        ? idx.map { lyrics.lineProgress(in: lines, index: $0, position: player.position) }
                        : nil
                    ZStack {
                        VStack(spacing: 1) {
                            KaraokeText(text: texts.primary.isEmpty ? "♪" : texts.primary,
                                        progress: progress,
                                        font: .system(size: 12.5, weight: .semibold, design: .rounded),
                                        color: .white.opacity(0.92))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            if let secondary = texts.secondary {
                                Text(secondary.isEmpty ? " " : secondary)
                                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.55))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                        }
                        .id(idx ?? -1)
                        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                                removal: .opacity))
                    }
                    .animation(.easeOut(duration: 0.25), value: idx)
                }
                .padding(.horizontal, 16)
                // Satu sisi disembunyikan → lirik pindah ke sisi yang tersisa.
                .padding(.leading, vm.hiddenEar == .left ? vm.earWidth : 0)
                .padding(.trailing, vm.hiddenEar == .right ? vm.earWidth : 0)
                .frame(height: (lyrics.compactIsDouble ? vm.compactDoubleLyricHeight : vm.compactLyricHeight) - 4)
                .clipped()
                .opacity(vm.lyricLineSuppressed ? 0 : (vm.lyricLineFaded ? 0.15 : 1))
            }
        }
    }
}
