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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                leftEar
                    .opacity(musicEarHidden(.left) ? 0 : 1)
                Spacer(minLength: vm.baseWidth)
                rightEar
                    .opacity(musicEarHidden(.right) ? 0 : 1)
            }
            .padding(.horizontal, 14)
            .frame(height: vm.notchSize.height)
            .background {
                // Bagian telinga musik di luar tombol: klik = singkirkan telinga itu.
                // Tombol (putar/jeda, next) ada di atas lapisan ini, jadi kliknya tidak terganggu.
                HStack(spacing: 0) {
                    earHideArea(.left)
                    Spacer(minLength: 0)
                    earHideArea(.right)
                }
            }

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
                        .transition(reduceMotion ? .opacity
                                    : .asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                                  removal: .opacity))
                    }
                    .animation(.easeOut(duration: 0.25), value: idx)
                }
                .padding(.horizontal, 16)
                // Satu sisi disembunyikan → lirik pindah ke sisi yang tersisa.
                // Telinga musik hanya memudar, jadi liriknya tidak perlu bergeser.
                .padding(.leading, vm.hiddenEar == .left && !vm.earsAreControls ? vm.earWidth : 0)
                .padding(.trailing, vm.hiddenEar == .right && !vm.earsAreControls ? vm.earWidth : 0)
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
        } else if vm.earOwner == .prayerSoon {
            // Nama waktu di kiri, sisa menit di kanan: "Dzuhur ▮notch▮ 9m". Satu telinga terlalu sempit untuk keduanya.
            Text(prayerSoonLabel)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.prayerAccent)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: earTextWidth, alignment: .leading)
        } else if isPrayerOwner {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.prayerAccent)
                .frame(width: 20, height: 20)
        } else if vm.earOwner == .pomodoro {
            TimelineView(.animation(minimumInterval: 1, paused: pomodoro.isPaused || pomodoro.phase == .idle)) { ctx in
                ZStack {
                    ProgressRing(progress: pomodoro.phase == .idle ? 1 : pomodoro.progress(at: ctx.date),
                                 color: pomodoro.phase.isBreak ? .breakAccent : .focusAccent)
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
        } else if vm.hoveredEar == .left {
            EarButton(symbol: player.isPlaying ? "pause.fill" : "play.fill") { player.playPause() }
        } else {
            ArtworkView(image: player.artwork, size: 20, corner: 5)
                .transition(.opacity)
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
                .minimumScaleFactor(0.75)
                .frame(maxWidth: earTextWidth, alignment: .trailing)
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
            .foregroundStyle(pomodoro.phase.isBreak ? Color.breakAccent : Color.focusAccent)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: earTextWidth, alignment: .trailing)
        } else if vm.hoveredEar == .right {
            EarButton(symbol: "forward.fill") { player.next() }
        } else {
            EqualizerView(isPlaying: player.isPlaying, color: vm.accent(for: player))
                .frame(width: 20, height: 14)
                .transition(.opacity)
        }
    }

    private func musicEarHidden(_ side: EarSide) -> Bool {
        vm.earsAreControls && vm.hiddenEar == side
    }

    @ViewBuilder private func earHideArea(_ side: EarSide) -> some View {
        if vm.hoveredEar == side {
            Color.clear
                .frame(width: vm.earWidth)
                .contentShape(Rectangle())
                .onTapGesture { vm.hideEar?(side) }
        } else {
            Color.clear.frame(width: vm.earWidth)
        }
    }

    /// Lebar teks yang aman di satu telinga (tidak masuk ke bawah notch fisik).
    private var earTextWidth: CGFloat { max(vm.earWidth - 16, 30) }

    /// Telinga kanan: "14m" (menjelang), atau nama waktu saat baru masuk ("Ashar").
    private var prayerText: String {
        let now = prayer.now
        if vm.earOwner == .prayerNow, let last = prayer.last(before: now) {
            return last.prayer.title
        }
        guard let next = prayer.next(after: now) else { return "" }
        let minutes = max(Int((next.time.timeIntervalSince(now) / 60).rounded(.up)), 0)
        return "\(minutes)m"
    }

    /// Telinga kiri saat menjelang: "Dzuhur", atau "Buka" saat Ramadan.
    private var prayerSoonLabel: String {
        guard let next = prayer.next(after: prayer.now) else { return "" }
        return next.prayer == .maghrib && prayer.isRamadan ? L("Buka", "Iftar") : next.prayer.title
    }
}

/// Tombol kecil yang muncul di telinga musik saat kursor menunjuknya.
private struct EarButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle().inset(by: -8))
        }
        .buttonStyle(.plain)
        .transition(.opacity.combined(with: .scale(scale: 0.7)))
    }
}
