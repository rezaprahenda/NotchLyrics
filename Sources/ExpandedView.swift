import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Expanded

extension Notification.Name {
    /// Minta AppDelegate membuka jendela Pengaturan (dari tombol "+" di tab).
    static let popocuOpenSettings = Notification.Name("popocu.openSettings")
}

/// Halaman panel penuh (satu per modul).
enum ExpandedPage: String, CaseIterable {
    case music, focus, prayer, shelf, mirror, clipboard

    var title: String {
        switch self {
        case .music: return L("Musik", "Music")
        case .focus: return L("Fokus", "Focus")
        case .prayer: return L("Salat", "Prayer")
        case .shelf: return L("Rak", "Shelf")
        case .mirror: return L("Cermin", "Mirror")
        case .clipboard: return L("Klip", "Clipboard")
        }
    }

    var symbol: String {
        switch self {
        case .music: return "music.note"
        case .focus: return "timer"
        case .prayer: return "moon.stars"
        case .shelf: return "tray"
        case .mirror: return "camera"
        case .clipboard: return "doc.on.clipboard"
        }
    }
}

struct ExpandedView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var player: PlayerMonitor
    @ObservedObject var lyrics: LyricsStore
    @ObservedObject var pomodoro: PomodoroModule
    @ObservedObject var prayer: PrayerModule
    @ObservedObject var shelf: ShelfModule
    @ObservedObject var mirror: MirrorModule
    @ObservedObject var clipboard: ClipboardModule

    /// Hanya modul yang aktif yang punya tab.
    private var pages: [ExpandedPage] {
        ExpandedPage.allCases.filter {
            switch $0 {
            case .music: return true
            case .focus: return pomodoro.enabled
            case .prayer: return prayer.enabled
            case .shelf: return shelf.enabled
            case .mirror: return mirror.enabled
            case .clipboard: return clipboard.enabled
            }
        }
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
            case .prayer:
                PrayerPage(prayer: prayer)
            case .shelf:
                ShelfPage(shelf: shelf)
            case .mirror:
                MirrorPage(mirror: mirror)
            case .clipboard:
                ClipboardPage(clipboard: clipboard)
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
            Button {
                NotificationCenter.default.post(name: .popocuOpenSettings, object: nil)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L("Tambah modul (Salat, Cermin, Klip…)", "Add modules (Prayer, Mirror, Clipboard…)"))
            .accessibilityLabel(L("Tambah modul", "Add modules"))
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

    private var showsLyricsToolbar: Bool {
        if lyrics.isPickerOpen { return false }
        switch lyrics.state {
        case .synced, .plain: return true
        default: return false
        }
    }

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
                    // Kontrol musik + tombol lirik di kanan, supaya tidak menutupi baris lirik.
                    VStack(alignment: .trailing, spacing: 5) {
                        ControlsView(player: player)
                        if showsLyricsToolbar {
                            LyricsToolbar(lyrics: lyrics, showOffset: lyrics.state.syncedLines != nil)
                        }
                    }
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

// MARK: - Halaman Rak

struct ShelfPage: View {
    @ObservedObject var shelf: ShelfModule
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 10) {
            ScrollView(.vertical, showsIndicators: false) {
                if shelf.items.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "tray.and.arrow.down")
                            .font(.system(size: 22))
                            .foregroundStyle(Color.shelfAccent)
                        Text(L("Seret file ke notch untuk dititipkan di sini.", "Drag files onto the notch to keep them here."))
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 8)], spacing: 8) {
                        ForEach(shelf.items, id: \.self) { url in
                            ShelfChip(url: url, shelf: shelf)
                        }
                    }
                    .padding(10)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.shelfAccent.opacity(targeted ? 0.95 : 0.45),
                              style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.shelfAccent.opacity(targeted ? 0.12 : 0)))
            .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
                for provider in providers {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        guard let url else { return }
                        DispatchQueue.main.async { shelf.add([url]) }
                    }
                }
                return true
            }

            HStack(spacing: 8) {
                PeekButton(title: "AirDrop", filled: true, tint: .shelfAccent) { shelf.airDrop() }
                    .disabled(shelf.items.isEmpty)
                    .opacity(shelf.items.isEmpty ? 0.5 : 1)
                PeekButton(title: L("Kosongkan", "Clear"), filled: false, tint: .shelfAccent) { shelf.clear() }
                    .disabled(shelf.items.isEmpty)
                Spacer()
                Text(L("Seret keluar untuk memindahkan", "Drag out to move"))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .onAppear { shelf.pruneMissing() }
    }
}

/// Satu file di Rak: bisa diseret keluar, diklik untuk dibuka, atau dihapus dari rak.
struct ShelfChip: View {
    let url: URL
    @ObservedObject var shelf: ShelfModule
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 22, height: 22)
            Text(url.lastPathComponent)
                .font(.system(size: 11.5))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            if hovering {
                Button { shelf.remove(url) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Hapus dari rak", "Remove from shelf"))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(hovering ? 0.16 : 0.1)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { shelf.open(url) }
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .help(url.path)
        .contextMenu {
            Button(L("Buka", "Open")) { shelf.open(url) }
            Button(L("Tampilkan di Finder", "Show in Finder")) { shelf.reveal(url) }
            Button(L("Hapus dari rak", "Remove from shelf")) { shelf.remove(url) }
        }
    }
}

// MARK: - Halaman Salat

struct PrayerPage: View {
    @ObservedObject var prayer: PrayerModule

    private var rows: [Prayer] {
        let base: [Prayer] = [.fajr, .sunrise, .dhuhr, .asr, .maghrib, .isha]
        return prayer.isRamadan ? [.imsak] + base : base
    }

    var body: some View {
        if prayer.today.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "location.slash")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.prayerAccent)
                Text(prayer.locationDenied
                     ? L("Izin lokasi ditolak. Pilih kota di Pengaturan › Salat.",
                         "Location access is off. Choose a city in Settings › Prayer.")
                     : L("Menunggu lokasi… atau pilih kota di Pengaturan › Salat.",
                         "Waiting for location… or choose a city in Settings › Prayer."))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                if !prayer.locationDenied {
                    PeekButton(title: L("Izinkan lokasi", "Allow location"), filled: true, tint: .prayerAccent) {
                        prayer.refreshLocation()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(spacing: 14) {
                nextCard
                    .frame(width: 196)
                    .frame(maxHeight: .infinity)
                timetable
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Kartu "berikutnya": nama waktu, jam besar, hitung mundur, progres sejak waktu sebelumnya.
    @ViewBuilder private var nextCard: some View {
        let now = prayer.now
        VStack(alignment: .leading, spacing: 3) {
            Text(L("BERIKUTNYA", "NEXT"))
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(Color.prayerAccent.opacity(0.9))
            if let next = prayer.next(after: now) {
                Text(next.prayer == .maghrib && prayer.isRamadan ? L("Maghrib · berbuka", "Maghrib · iftar") : next.prayer.title)
                    .font(.system(size: 15, weight: .semibold))
                Text(prayer.timeText(next.time))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.prayerAccent)
                Text(L("\(countdown(to: next.time)) lagi", "in \(countdown(to: next.time))"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                Spacer(minLength: 6)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule().fill(Color.prayerAccent)
                            .frame(width: g.size.width * progress(until: next.time, now: now))
                    }
                }
                .frame(height: 4)
            }
            Spacer(minLength: 6)
            Text(prayer.placeName.isEmpty ? prayer.hijriDate : "\(prayer.placeName) · \(prayer.hijriDate)")
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.prayerAccent.opacity(0.12)))
    }

    /// Daftar waktu, dibagi rata dari atas ke bawah; yang sudah lewat diredupkan.
    private var timetable: some View {
        let now = prayer.now
        let next = prayer.next(after: now)?.prayer
        return VStack(spacing: 2) {
            ForEach(rows, id: \.self) { p in
                let isNext = p == next
                let passed = (prayer.today[p] ?? .distantFuture) < now && !isNext
                HStack {
                    Text(p.title)
                    Spacer()
                    Text(prayer.timeText(prayer.today[p]))
                        .monospacedDigit()
                }
                .font(.system(size: 13, weight: isNext ? .semibold : .regular))
                .foregroundStyle(isNext ? Color.prayerAccent
                                 : .white.opacity(passed ? 0.35 : (p.isObligatory ? 0.9 : 0.55)))
                .padding(.horizontal, 12)
                .frame(maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isNext ? Color.prayerAccent.opacity(0.16) : .clear))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func countdown(to date: Date) -> String {
        let minutes = max(Int((date.timeIntervalSince(prayer.now) / 60).rounded(.up)), 0)
        let h = minutes / 60, m = minutes % 60
        return h > 0 ? L("\(h) j \(m) m", "\(h)h \(m)m") : L("\(m) menit", "\(m) min")
    }

    /// Progres dari waktu salat sebelumnya (atau tengah malam) menuju waktu berikutnya.
    private func progress(until next: Date, now: Date) -> Double {
        let start = prayer.last(before: now)?.time ?? Calendar.current.startOfDay(for: now)
        let total = next.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        return min(max(now.timeIntervalSince(start) / total, 0), 1)
    }
}

// MARK: - Halaman Fokus

struct FocusPage: View {
    @ObservedObject var pomodoro: PomodoroModule

    private var accent: Color {
        let phase = pomodoro.phase == .idle ? (pomodoro.waitingFor ?? .focus) : pomodoro.phase
        return phase.isBreak ? .breakAccent : .focusAccent
    }

    var body: some View {
        HStack(spacing: 22) {
            TimelineView(.animation(minimumInterval: 1, paused: pomodoro.isPaused || pomodoro.phase == .idle)) { ctx in
                ZStack {
                    ProgressRing(progress: pomodoro.phase == .idle ? 0 : pomodoro.progress(at: ctx.date),
                                 color: accent, lineWidth: 9)
                    VStack(spacing: 2) {
                        Text(clockText(at: ctx.date))
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text(phaseLabel)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(accent)
                    }
                }
                .frame(width: 164, height: 164)
            }

            VStack(alignment: .leading, spacing: 12) {
                sessionDots
                controls
                if pomodoro.phase == .idle && pomodoro.waitingFor == nil {
                    presets
                }
                Spacer(minLength: 0)
                stats
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.vertical, 6)
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
                Capsule()
                    .fill(i < pomodoro.cycleFocusDone ? Color.focusAccent : Color.white.opacity(0.18))
                    .frame(width: 18, height: 5)
            }
            Text(L("sesi \(sessionNumber(total)) dari \(total)", "session \(sessionNumber(total)) of \(total)"))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))
                .padding(.leading, 4)
        }
    }

    /// Sesi yang sedang berjalan atau akan dimulai berikutnya; saat istirahat: sesi yang baru selesai.
    private func sessionNumber(_ total: Int) -> Int {
        let upcoming = pomodoro.phase == .focus
            || pomodoro.waitingFor == .focus
            || (pomodoro.phase == .idle && pomodoro.waitingFor == nil)
        return min(max(pomodoro.cycleFocusDone + (upcoming ? 1 : 0), 1), total)
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

    /// Dua kartu statistik hari ini.
    private var stats: some View {
        let h = pomodoro.todayFocusMinutes / 60
        let m = pomodoro.todayFocusMinutes % 60
        let time = h > 0 ? L("\(h) j \(m) m", "\(h)h \(m)m") : L("\(m) mnt", "\(m) min")
        return HStack(spacing: 8) {
            statTile(value: "\(pomodoro.todaySessions)", label: L("sesi hari ini", "sessions today"))
            statTile(value: time, label: L("waktu fokus", "focus time"))
        }
    }

    private func statTile(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.55))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.07)))
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

/// Deretan tombol kecil lirik (di header, di bawah kontrol musik): Aa, terjemahan, karaoke, offset, pilih lirik.
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
