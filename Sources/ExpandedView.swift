import SwiftUI
import AppKit

// MARK: - Expanded

/// Halaman panel penuh (satu per modul).
enum ExpandedPage: String, CaseIterable {
    case music, focus

    var title: String {
        switch self {
        case .music: return L("Musik", "Music")
        case .focus: return L("Fokus", "Focus")
        }
    }

    var symbol: String {
        switch self {
        case .music: return "music.note"
        case .focus: return "timer"
        }
    }
}

struct ExpandedView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var player: PlayerMonitor
    @ObservedObject var lyrics: LyricsStore
    @ObservedObject var pomodoro: PomodoroModule

    /// Hanya modul yang aktif yang punya tab.
    private var pages: [ExpandedPage] {
        ExpandedPage.allCases.filter { $0 != .focus || pomodoro.enabled }
    }

    private var page: ExpandedPage {
        pages.contains(vm.expandedPage) ? vm.expandedPage : .music
    }

    var body: some View {
        VStack(spacing: 10) {
            Color.clear.frame(height: max(vm.notchSize.height - 6, 0))

            if pages.count > 1 {
                PageTabs(pages: pages, selection: page) { selected in
                    withAnimation(.easeInOut(duration: 0.2)) { vm.expandedPage = selected }
                }
            }

            switch page {
            case .music:
                MusicPage(vm: vm, player: player, lyrics: lyrics)
            case .focus:
                FocusPage(pomodoro: pomodoro)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
        .foregroundStyle(.white)
    }
}

/// Tab ikon di tengah, sejajar notch; label hanya pada tab aktif.
struct PageTabs: View {
    let pages: [ExpandedPage]
    let selection: ExpandedPage
    let select: (ExpandedPage) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(pages, id: \.self) { p in
                let on = p == selection
                Button { select(p) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: p.symbol)
                            .font(.system(size: 11, weight: .semibold))
                        if on {
                            Text(p.title)
                                .font(.system(size: 11.5, weight: .semibold))
                        }
                    }
                    .foregroundStyle(.white.opacity(on ? 1 : 0.6))
                    .padding(.horizontal, on ? 11 : 9)
                    .frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(on ? 0.16 : 0)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(p.title)
                .accessibilityLabel(p.title)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.08)))
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Halaman Musik

struct MusicPage: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var player: PlayerMonitor
    @ObservedObject var lyrics: LyricsStore

    var body: some View {
        VStack(spacing: 12) {
            if let track = player.track {
                HStack(spacing: 12) {
                    ArtworkView(image: player.artwork, size: 50, corner: 10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                        Text(track.artist)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            Text(track.source.displayName)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(vm.accent(for: player).opacity(0.9))
                            SleepIndicator(player: player)
                        }
                    }
                    Spacer(minLength: 8)
                    ControlsView(player: player)
                }

                LyricsPanel(player: player, lyrics: lyrics)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                HStack(spacing: 14) {
                    ProgressBar(player: player, duration: track.duration)
                    VolumeControl(player: player)
                }
            } else {
                EmptyStateView(permissionDenied: player.permissionDenied, error: player.lastError)
            }
        }
    }
}

// MARK: - Halaman Fokus

struct FocusPage: View {
    @ObservedObject var pomodoro: PomodoroModule

    private var accent: Color {
        let phase = pomodoro.phase == .idle ? (pomodoro.waitingFor ?? .focus) : pomodoro.phase
        return phase.isBreak ? .prayerAccent : .focusAccent
    }

    var body: some View {
        HStack(spacing: 24) {
            TimelineView(.animation(minimumInterval: 1, paused: pomodoro.isPaused || pomodoro.phase == .idle)) { ctx in
                ZStack {
                    ProgressRing(progress: pomodoro.phase == .idle ? 0 : pomodoro.progress(at: ctx.date),
                                 color: accent, lineWidth: 7)
                    VStack(spacing: 2) {
                        Text(clockText(at: ctx.date))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text(phaseLabel)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .frame(width: 128, height: 128)
            }

            VStack(alignment: .leading, spacing: 11) {
                sessionDots
                controls
                if pomodoro.phase == .idle && pomodoro.waitingFor == nil {
                    presets
                }
                Text(statsText)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func clockText(at date: Date) -> String {
        if pomodoro.phase != .idle { return PomodoroCore.clock(pomodoro.remaining(at: date)) }
        let next = pomodoro.waitingFor ?? .focus
        return PomodoroCore.clock(PomodoroCore.duration(of: next, settings: pomodoro.settings))
    }

    private var phaseLabel: String {
        switch pomodoro.phase {
        case .focus: return pomodoro.isPaused ? L("Dijeda", "Paused") : L("Fokus", "Focus")
        case .shortBreak: return pomodoro.isPaused ? L("Dijeda", "Paused") : L("Istirahat", "Break")
        case .longBreak: return pomodoro.isPaused ? L("Dijeda", "Paused") : L("Istirahat panjang", "Long break")
        case .idle:
            if let next = pomodoro.waitingFor {
                return next.isBreak ? L("Siap istirahat", "Ready for a break") : L("Siap fokus", "Ready to focus")
            }
            return L("Siap mulai", "Ready")
        }
    }

    private var sessionDots: some View {
        let total = max(pomodoro.settings.sessionsBeforeLongBreak, 1)
        return HStack(spacing: 5) {
            ForEach(0..<total, id: \.self) { i in
                Circle()
                    .fill(i < pomodoro.cycleFocusDone ? Color.focusAccent : Color.white.opacity(0.18))
                    .frame(width: 7, height: 7)
            }
            Text(L("sesi \(min(pomodoro.cycleFocusDone + (pomodoro.phase == .focus ? 1 : 0), total)) dari \(total)",
                   "session \(min(pomodoro.cycleFocusDone + (pomodoro.phase == .focus ? 1 : 0), total)) of \(total)"))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.leading, 4)
        }
    }

    @ViewBuilder private var controls: some View {
        HStack(spacing: 8) {
            if pomodoro.phase != .idle {
                PeekButton(title: pomodoro.isPaused ? L("Lanjut", "Resume") : L("Jeda", "Pause"),
                           filled: true, tint: accent) { pomodoro.togglePause() }
                PeekButton(title: L("Lewati", "Skip"), filled: false, tint: accent) { pomodoro.skipCurrent() }
                PeekButton(title: L("Stop", "Stop"), filled: false, tint: accent) { pomodoro.stop() }
            } else if pomodoro.waitingFor != nil {
                PeekButton(title: L("Mulai", "Start"), filled: true, tint: accent) { pomodoro.acceptNext() }
                PeekButton(title: L("Lewati", "Skip"), filled: false, tint: accent) { pomodoro.skipNext() }
                PeekButton(title: L("Stop", "Stop"), filled: false, tint: accent) { pomodoro.stop() }
            } else {
                PeekButton(title: L("Mulai fokus", "Start focus"), filled: true, tint: accent) { pomodoro.start(.focus) }
            }
        }
    }

    private var presets: some View {
        HStack(spacing: 6) {
            ForEach(Array(PomodoroSettings.presets.enumerated()), id: \.offset) { _, preset in
                let on = pomodoro.settings.focusMinutes == preset.focus && pomodoro.settings.shortBreakMinutes == preset.rest
                PillToggle(label: "\(preset.focus) / \(preset.rest)", symbol: nil, isOn: on) {
                    pomodoro.settings.focusMinutes = preset.focus
                    pomodoro.settings.shortBreakMinutes = preset.rest
                }
            }
        }
    }

    private var statsText: String {
        let h = pomodoro.todayFocusMinutes / 60
        let m = pomodoro.todayFocusMinutes % 60
        let time = h > 0 ? L("\(h) j \(m) m", "\(h)h \(m)m") : L("\(m) menit", "\(m) min")
        return L("Hari ini: \(pomodoro.todaySessions) sesi · \(time)", "Today: \(pomodoro.todaySessions) sessions · \(time)")
    }
}

struct LyricsPanel: View {
    @ObservedObject var player: PlayerMonitor
    @ObservedObject var lyrics: LyricsStore

    var body: some View {
        if lyrics.isPickerOpen {
            LyricsPickerView(lyrics: lyrics, trackDuration: player.track?.duration ?? 0)
        } else {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch lyrics.state {
        case .synced(let lines):
            SyncedLyricsView(lines: lines, player: player, lyrics: lyrics)
                .overlay(alignment: .topTrailing) {
                    LyricsToolbar(lyrics: lyrics, showOffset: true)
                }
                .overlay(alignment: .bottom) {
                    TranslationErrorNote(lyrics: lyrics)
                }
        case .plain(let lines):
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Lirik tidak tersinkron", "Lyrics not synced"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                    ForEach(Array(lines.enumerated()), id: \.offset) { item in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.element)
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.8))
                            if lyrics.romanizationEnabled, let latin = lyrics.romanized[item.offset] {
                                Text(latin)
                                    .font(.system(size: 12, weight: .medium))
                                    .italic()
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                            if lyrics.translationEnabled, let translated = lyrics.translations[item.offset] {
                                Text(translated)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.white.opacity(0.45))
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .overlay(alignment: .topTrailing) { LyricsToolbar(lyrics: lyrics, showOffset: false) }
            .overlay(alignment: .bottom) { TranslationErrorNote(lyrics: lyrics) }
        case .loading:
            message(L("Mencari lirik…", "Searching lyrics…"), withSearch: false)
        case .instrumental:
            message("♪ Instrumental", withSearch: true)
        case .notFound, .none:
            message(L("Lirik tidak tersedia untuk lagu ini", "No lyrics available for this song"), withSearch: true)
        }
    }

    private func message(_ s: String, withSearch: Bool) -> some View {
        VStack(spacing: 10) {
            Text(s)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.5))
            if withSearch {
                Button {
                    lyrics.isPickerOpen = true
                } label: {
                    Label(L("Cari lirik lain", "Find other lyrics"), systemImage: "magnifyingglass")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Deretan tombol kecil di pojok kanan atas lirik: Aa, ID, offset, pilih lirik.
struct LyricsToolbar: View {
    @ObservedObject var lyrics: LyricsStore
    let showOffset: Bool

    var body: some View {
        HStack(spacing: 6) {
            if lyrics.hasRomanization {
                PillToggle(label: "Aa", symbol: nil, isOn: lyrics.romanizationEnabled) {
                    lyrics.romanizationEnabled.toggle()
                }
                .help(L("Tampilkan huruf latin (romanisasi)", "Show romanization"))
            }
            if #available(macOS 15.0, *) {
                TranslateToggle(lyrics: lyrics)
            }
            if showOffset {
                PillToggle(label: nil, symbol: "music.mic", isOn: lyrics.karaokeEnabled) {
                    lyrics.karaokeEnabled.toggle()
                }
                .help(L("Karaoke: baris terisi mengikuti lagu", "Karaoke: fill lines as they are sung"))
                OffsetControl(lyrics: lyrics)
            }
            PillToggle(label: nil, symbol: "text.magnifyingglass", isOn: lyrics.hasOverride) {
                lyrics.isPickerOpen = true
            }
            .help(L("Pilih lirik lain", "Choose other lyrics"))
        }
    }
}

/// Teks yang terisi dari kiri ke kanan sesuai `progress` (0…1). `progress` nil = teks biasa.
struct KaraokeText: View {
    let text: String
    let progress: Double?
    let font: Font
    let color: Color

    var body: some View {
        if let progress {
            Text(text)
                .font(font)
                .foregroundStyle(color.opacity(0.4))
                .overlay(alignment: .leading) {
                    Text(text)
                        .font(font)
                        .foregroundStyle(color)
                        .mask(alignment: .leading) {
                            GeometryReader { g in
                                Rectangle().frame(width: g.size.width * min(max(progress, 0), 1))
                            }
                        }
                }
        } else {
            Text(text)
                .font(font)
                .foregroundStyle(color)
        }
    }
}

/// Tombol kapsul kecil yang bisa menyala/mati.
struct PillToggle: View {
    let label: String?
    let symbol: String?
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                }
                if let label {
                    Text(label).font(.system(size: 10, weight: .bold))
                }
            }
            .foregroundStyle(.white.opacity(isOn ? 1 : 0.55))
            .padding(.horizontal, 7)
            .frame(minWidth: 24)
            .frame(height: 22)
            .background(Capsule().fill(Color.white.opacity(isOn ? 0.22 : 0.08)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
