import SwiftUI
import AppKit

// MARK: - Compact

struct CompactView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var player: PlayerMonitor
    @ObservedObject var lyrics: LyricsStore
    @ObservedObject var pomodoro: PomodoroModule
    @ObservedObject var prayer: PrayerModule
    @ObservedObject var shelf: ShelfModule
    let showLine: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                leftEar
                Spacer(minLength: vm.baseWidth)
                rightEar
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
        .overlay(alignment: .bottomLeading) {
            // Progres sesi pomodoro: garis tipis di tepi bawah.
            if vm.earOwner == .pomodoro, pomodoro.phase != .idle {
                TimelineView(.animation(minimumInterval: 1, paused: pomodoro.isPaused)) { ctx in
                    GeometryReader { g in
                        Rectangle()
                            .fill(Color.focusAccent)
                            .frame(width: g.size.width * pomodoro.progress(at: ctx.date), height: 2)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                }
                .frame(height: 2)
            }
        }
    }

    // MARK: Telinga

    private var isPrayerOwner: Bool { vm.earOwner == .prayerNow || vm.earOwner == .prayerSoon }

    @ViewBuilder private var leftEar: some View {
        if vm.earOwner == .shelf {
            Image(systemName: "tray.full")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.shelfAccent)
                .frame(width: 20, height: 20)
        } else if isPrayerOwner {
            Image(systemName: vm.earOwner == .prayerNow ? "moon.stars.fill" : "moon.stars")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.prayerAccent)
                .frame(width: 20, height: 20)
        } else if vm.earOwner == .pomodoro {
            TimelineView(.animation(minimumInterval: 1, paused: pomodoro.isPaused || pomodoro.phase == .idle)) { ctx in
                ZStack {
                    ProgressRing(progress: pomodoro.phase == .idle ? 1 : pomodoro.progress(at: ctx.date),
                                 color: pomodoro.phase.isBreak ? .prayerAccent : .focusAccent)
                    if player.track != nil {
                        ArtworkView(image: player.artwork, size: 15, corner: 4)
                    } else {
                        Image(systemName: "timer")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.focusAccent)
                    }
                }
                .frame(width: 24, height: 24)
            }
        } else {
            ArtworkView(image: player.artwork, size: 20, corner: 5)
        }
    }

    @ViewBuilder private var rightEar: some View {
        if vm.earOwner == .shelf {
            Text("\(shelf.items.count)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.shelfAccent)
                .fixedSize()
        } else if isPrayerOwner {
            Text(prayerText)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.prayerAccent)
                .lineLimit(1)
                .fixedSize()
        } else if vm.earOwner == .pomodoro {
            Group {
                if let next = pomodoro.waitingFor {
                    Text(next.isBreak ? L("rehat?", "break?") : L("fokus?", "focus?"))
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text(PomodoroCore.clock(pomodoro.remaining(at: ctx.date)))
                            .opacity(pomodoro.isPaused ? 0.5 : 1)
                    }
                }
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(pomodoro.phase.isBreak ? Color.prayerAccent : Color.focusAccent)
            .lineLimit(1)
            .fixedSize()
        } else {
            EqualizerView(isPlaying: player.isPlaying, color: vm.accent(for: player))
                .frame(width: 20, height: 14)
        }
    }

    /// "Ashar 14m", "Buka 42m" (Ramadan), atau "Ashar" saat waktunya baru masuk.
    private var prayerText: String {
        let now = prayer.now
        if vm.earOwner == .prayerNow, let last = prayer.last(before: now) {
            return last.prayer.title
        }
        guard let next = prayer.next(after: now) else { return "" }
        let minutes = max(Int((next.time.timeIntervalSince(now) / 60).rounded(.up)), 0)
        let label = next.prayer == .maghrib && prayer.isRamadan ? L("Buka", "Iftar") : next.prayer.title
        return "\(label) \(minutes)m"
    }
}
