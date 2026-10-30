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

    /// Warna tab aktif. Musik mengikuti warna cover / aplikasi pemutar.
    func accent(music: Color) -> Color {
        switch self {
        case .music: return music
        case .focus: return .focusAccent
        case .prayer: return .prayerAccent
        case .shelf: return .shelfAccent
        case .mirror: return .mirrorAccent
        case .clipboard: return .clipboardAccent
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
            PanelHeader(notchWidth: vm.notchSize.width)
                .frame(height: max(vm.notchSize.height - 6, 0))

            if pages.count > 1 {
                PageTabs(pages: pages, selection: page,
                         musicAccent: player.track == nil ? .musicAccent : vm.accent(for: player)) { selected in
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
    let musicAccent: Color
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
                    .foregroundStyle(on ? p.accent(music: musicAccent).lighter(0.45) : .white.opacity(0.6))
                    .padding(.horizontal, on ? 11 : 9)
                    .frame(height: 24)
                    .background {
                        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
                        if on {
                            let accent = p.accent(music: musicAccent)
                            shape.fill(accent.opacity(0.2))
                                .overlay(shape.strokeBorder(accent.opacity(0.28), lineWidth: 1))
                        }
                    }
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
        .background {
            let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
            shape.fill(Color.white.opacity(0.07))
                .overlay(shape.strokeBorder(Color.white.opacity(0.05), lineWidth: 1))
        }
        .frame(maxWidth: .infinity)
    }
}

/// Baris di samping notch: logo + sapaan di kiri, jam di kanan.
struct PanelHeader: View {
    let notchWidth: CGFloat
    @ObservedObject private var weather = WeatherModule.shared

    var body: some View {
        TimelineView(.everyMinute) { ctx in
            GeometryReader { g in
                // Tiap sisi hanya boleh memakai ruang di kiri/kanan notch fisik, supaya tidak tertutup notch.
                let side = max((g.size.width - notchWidth) / 2 - 10, 0)
                HStack(spacing: 0) {
                    leftSide(at: ctx.date, width: side)
                        .frame(width: side, alignment: .leading)
                    Spacer(minLength: 0)
                    Text(ctx.date, format: .dateTime.hour().minute())
                        .monospacedDigit()
                        .lineLimit(1)
                        .frame(width: side, alignment: .trailing)
                }
                .frame(maxHeight: .infinity)
            }
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(.white.opacity(0.75))
        }
        .onAppear { weather.refreshIfStale() }
    }

    /// Logo + sapaan + cuaca. Kalau tidak muat, nama dilepas dulu, lalu sapaannya; cuaca dipertahankan.
    /// ViewThatFits memilih versi terpanjang yang benar-benar muat (tanpa "Morni…").
    @ViewBuilder private func leftSide(at date: Date, width: CGFloat) -> some View {
        ViewThatFits(in: .horizontal) {
            leftRow(text: Self.greeting(at: date))
            leftRow(text: Self.greeting(at: date, withName: false))
            leftRow(text: nil)
        }
    }

    private func leftRow(text: String?) -> some View {
        let w = weather.enabled ? weather.current : nil
        return HStack(spacing: 6) {
            Image(nsImage: Brand.mascot)
                .resizable()
                .interpolation(.high)
                .frame(width: 22, height: 22)
            if let text {
                Text(text)
            }
            if let w {
                if text != nil { Text("·").foregroundStyle(.white.opacity(0.35)) }
                HStack(spacing: 4) {
                    Image(systemName: w.symbol)
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 11))
                    Text(w.temperatureText)
                        .monospacedDigit()
                }
                .help(weatherHelp(w))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(w.summary), \(w.temperatureText)")
            }
        }
        .fixedSize()
    }

    /// "Berawan · hujan mulai ±16.00 · 3 jam: 27° 26° 26°"
    private func weatherHelp(_ w: WeatherNow) -> String {
        let fmt: (Date) -> String = { $0.formatted(.dateTime.hour().minute()) }
        var parts = [w.summary]
        if let hint = WeatherCore.rainHint(w, format: fmt) { parts.append(hint) }
        let next = w.nextHours.prefix(3).map { "\(fmt($0.hour)) \(WeatherCore.degrees($0.temperature))" }
        if !next.isEmpty { parts.append(next.joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }

    static let firstName: String = {
        NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
    }()

    static func greeting(at date: Date, withName: Bool = true) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        let part: String
        switch hour {
        case 4..<11: part = L("Pagi", "Morning")
        case 11..<15: part = L("Siang", "Afternoon")
        case 15..<18: part = L("Sore", "Afternoon")
        default: part = L("Malam", "Evening")
        }
        return firstName.isEmpty || !withName ? part : "\(part), \(firstName)"
    }
}

// MARK: - Halaman Musik

struct MusicPage: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var player: PlayerMonitor
    @ObservedObject var lyrics: LyricsStore
    @Environment(\.panelStyle) private var style

    private var showsLyricsToolbar: Bool {
        if lyrics.isPickerOpen { return false }
        switch lyrics.state {
        case .synced, .plain: return true
        default: return false
        }
    }

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let accent = vm.accent(for: player)
        VStack(spacing: 12) {
            if let track = player.track {
                HStack(spacing: 12) {
                    ArtworkView(image: player.artwork, size: 58, corner: 12)
                        .shadow(color: .black.opacity(style == .vivid ? 0.45 : 0), radius: 8, y: 4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                        Text(track.artist)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            HStack(spacing: 4) {
                                Circle().fill(accent).frame(width: 6, height: 6)
                                Text(track.source.displayName)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
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
                    ProgressBar(player: player, duration: track.duration, tint: accent)
                    HStack(spacing: 4) {
                        AudioOutputButton()
                        VolumeControl(player: player)
                    }
                }
            } else {
                EmptyStateView(permissionDenied: player.permissionDenied, error: player.lastError)
            }
        }
        .background {
            // Cahaya warna cover dari pojok kiri bawah (jauh dari notch), melebar sampai tepi panel.
            if player.track != nil && !reduceTransparency && style == .vivid {
                RadialGradient(colors: [accent.opacity(0.24), accent.opacity(0.06), .clear],
                               center: .bottomLeading, startRadius: 0, endRadius: 300)
                    .padding(.horizontal, -20)
                    .padding(.bottom, -14)
                    .allowsHitTesting(false)
                    .animation(.easeInOut(duration: 0.6), value: player.artworkColor)
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
    @Environment(\.panelStyle) private var style
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let obligatory: [Prayer] = [.fajr, .dhuhr, .asr, .maghrib, .isha]

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
            HStack(spacing: 12) {
                nextCard
                    .frame(width: 158)
                    .frame(maxHeight: .infinity)
                arcCard
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Kartu "berikutnya": nama waktu, jam besar bercahaya, hitung mundur, tempat & kiblat.
    @ViewBuilder private var nextCard: some View {
        let now = prayer.now
        VStack(alignment: .leading, spacing: 1) {
            Text(L("BERIKUTNYA", "NEXT"))
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(Color.prayerAccent.lighter(0.4))
            if let next = prayer.next(after: now) {
                Text(next.prayer == .maghrib && prayer.isRamadan ? L("Maghrib · berbuka", "Maghrib · iftar") : next.prayer.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(prayer.timeText(next.time))
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.prayerAccent.lighter(0.35))
                Text(L("\(countdown(to: next.time)) lagi", "in \(countdown(to: next.time))"))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                Spacer(minLength: 8)
                // Progres sejak waktu salat sebelumnya.
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule().fill(Color.prayerAccent)
                            .frame(width: g.size.width * progress(until: next.time))
                    }
                }
                .frame(height: 4)
                .padding(.bottom, 8)
            } else {
                Spacer(minLength: 8)
            }
            HStack(spacing: 5) {
                Text(prayer.placeName.isEmpty ? prayer.hijriDate : prayer.placeName)
                    .lineLimit(1)
                if let q = prayer.qibla {
                    Spacer(minLength: 4)
                    Image(systemName: "location.north.fill")
                        .font(.system(size: 8))
                        .rotationEffect(.degrees(q))
                    Text("\(Int(q.rounded()))°")
                        .monospacedDigit()
                }
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.white.opacity(0.6))
            .help(prayer.qibla.map { L("Arah kiblat \(Int($0.rounded()))° dari utara", "Qibla \(Int($0.rounded()))° from north") } ?? "")
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .surfaceCard(tint: .prayerAccent)
    }

    /// Lengkung waktu salat wajib + pilihan suara & pengingat.
    private var arcCard: some View {
        let now = prayer.now
        let times = obligatory.compactMap { prayer.today[$0] }
        let position = times.count == obligatory.count ? PrayerCalc.position(of: now, in: times) : 0
        let next = prayer.next(after: now)
        let nextIndex = next.flatMap { n in obligatory.firstIndex(of: n.prayer) }

        return VStack(spacing: 4) {
            HStack {
                Text(extraLine)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                Spacer()
            }
            PrayerArc(count: obligatory.count, position: position, glow: !reduceTransparency && style == .vivid)
                .frame(maxHeight: 72)
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                ForEach(Array(obligatory.enumerated()), id: \.offset) { i, p in
                    let isNext = i == nextIndex
                    let passed = Double(i) < position && !isNext
                    let time = (isNext && next?.time != nil) ? next!.time : prayer.today[p]
                    VStack(spacing: 0) {
                        Text(p.title)
                            .font(.system(size: 10, weight: isNext ? .semibold : .regular))
                        Text(prayer.timeText(time))
                            .font(.system(size: 10.5, weight: .semibold))
                            .monospacedDigit()
                    }
                    .lineLimit(1)
                    .foregroundStyle(isNext ? Color.prayerAccent.lighter(0.4) : .white.opacity(passed ? 0.4 : 0.8))
                    .frame(maxWidth: .infinity)
                }
            }
            HStack(spacing: 8) {
                soundPicker
                Spacer(minLength: 0)
                MiniSwitch(label: L("Pengingat", "Reminders"), isOn: prayer.preAlerts, tint: .prayerAccent) {
                    prayer.preAlerts.toggle()
                }
                .help(L("Peek 15 & 5 menit sebelum waktu salat", "Peek 15 & 5 minutes before each prayer"))
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .surfaceCard()
    }

    /// "Imsak 04.00 · Terbit 05.24" (Imsak hanya saat Ramadan).
    private var extraLine: String {
        var parts: [String] = []
        if prayer.isRamadan, let imsak = prayer.today[.imsak] {
            parts.append("\(Prayer.imsak.title) \(prayer.timeText(imsak))")
        }
        if let sunrise = prayer.today[.sunrise] {
            parts.append("\(Prayer.sunrise.title) \(prayer.timeText(sunrise))")
        }
        parts.append(prayer.hijriDate)
        return parts.joined(separator: " · ")
    }

    /// Adzan (file sendiri, jika ada) / Nada (bunyi sistem) / Senyap.
    private var soundPicker: some View {
        var options: [(AdhanSound, String)] = []
        if !prayer.adhanFilePath.isEmpty || prayer.adhanSound == .file {
            options.append((.file, L("Adzan", "Adhan")))
        }
        options.append((.system, L("Nada", "Tone")))
        options.append((.off, L("Senyap", "Silent")))
        return HStack(spacing: 0) {
            ForEach(options, id: \.0) { option, title in
                let on = prayer.adhanSound == option
                Button { prayer.adhanSound = option } label: {
                    Text(title)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(on ? 1 : 0.55))
                        .padding(.horizontal, 9)
                        .frame(height: 20)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(on ? 0.15 : 0)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.07)))
    }

    /// Progres dari waktu salat sebelumnya (atau tengah malam) menuju waktu berikutnya.
    private func progress(until next: Date) -> Double {
        let now = prayer.now
        let start = prayer.last(before: now)?.time ?? Calendar.current.startOfDay(for: now)
        let total = next.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        return min(max(now.timeIntervalSince(start) / total, 0), 1)
    }

    private func countdown(to date: Date) -> String {
        let minutes = max(Int((date.timeIntervalSince(prayer.now) / 60).rounded(.up)), 0)
        let h = minutes / 60, m = minutes % 60
        return h > 0 ? L("\(h) j \(m) m", "\(h)h \(m)m") : L("\(m) menit", "\(m) min")
    }
}

/// Lengkung putus-putus seperti lintasan matahari; titik per waktu salat, titik bercahaya = sekarang.
struct PrayerArc: View {
    let count: Int
    /// Indeks pecahan posisi sekarang (0…count−1).
    let position: Double
    var glow = true

    var body: some View {
        Canvas { ctx, size in
            guard count > 1 else { return }
            let w = size.width, h = size.height
            let base = h - 5, amp = max(h - 14, 4)
            func y(atX x: CGFloat) -> CGFloat {
                let t = Double(x / w) * 2 - 1
                return base - amp * CGFloat(1 - t * t)
            }
            func point(_ index: Double) -> CGPoint {
                let x = CGFloat((index + 0.5) / Double(count)) * w
                return CGPoint(x: x, y: y(atX: x))
            }
            var curve = Path()
            let steps = 60
            for i in 0...steps {
                let x = 4 + (w - 8) * CGFloat(i) / CGFloat(steps)
                let p = CGPoint(x: x, y: y(atX: x))
                if i == 0 { curve.move(to: p) } else { curve.addLine(to: p) }
            }
            let dash = StrokeStyle(lineWidth: 2.2, lineCap: .round, dash: [3, 5])
            ctx.stroke(curve, with: .color(.white.opacity(0.18)), style: dash)

            let current = point(position)
            ctx.drawLayer { layer in
                layer.clip(to: Path(CGRect(x: 0, y: 0, width: current.x, height: h)))
                layer.stroke(curve, with: .color(Color.prayerAccent.opacity(0.9)), style: dash)
            }
            for i in 0..<count {
                let p = point(Double(i))
                let passed = Double(i) <= position
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7)),
                         with: .color(passed ? .prayerAccent : .white.opacity(0.3)))
            }
            ctx.drawLayer { layer in
                if glow { layer.addFilter(.shadow(color: Color.prayerAccent.opacity(0.9), radius: 6)) }
                layer.fill(Path(ellipseIn: CGRect(x: current.x - 6.5, y: current.y - 6.5, width: 13, height: 13)),
                           with: .color(Color.prayerAccent.lighter(0.4)))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Sakelar kecil bergaya iOS, sebagai tombol (panel notch tidak menerima fokus keyboard).
struct MiniSwitch: View {
    let label: String
    let isOn: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                ZStack(alignment: isOn ? .trailing : .leading) {
                    Capsule().fill(isOn ? tint : Color.white.opacity(0.2))
                    Circle().fill(.white).padding(2)
                }
                .frame(width: 26, height: 15)
                .animation(.easeInOut(duration: 0.15), value: isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? L("aktif", "on") : L("mati", "off"))
    }
}

// MARK: - Halaman Fokus

struct FocusPage: View {
    @ObservedObject var pomodoro: PomodoroModule
    @Environment(\.panelStyle) private var style

    private var accent: Color {
        let phase = pomodoro.phase == .idle ? (pomodoro.waitingFor ?? .focus) : pomodoro.phase
        return phase.isBreak ? .breakAccent : .focusAccent
    }

    var body: some View {
        HStack(spacing: 18) {
            TimelineView(.animation(minimumInterval: 1, paused: pomodoro.isPaused || pomodoro.phase == .idle)) { ctx in
                ZStack {
                    GlowRing(progress: pomodoro.phase == .idle ? 0 : pomodoro.progress(at: ctx.date),
                             color: accent, lineWidth: 10)
                    VStack(spacing: 0) {
                        Text(clockText(at: ctx.date))
                            .font(.system(size: 36, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                        Text("\(phaseLabel) · \(sessionNumber(totalSessions))/\(totalSessions)")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(accent.lighter(0.4))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: 124)
                    }
                }
                .frame(width: 146, height: 146)
            }

            // Kolom kanan setinggi cincin: tombol di atas, kartu statistik di bawah.
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    controls
                    if pomodoro.phase == .idle && pomodoro.waitingFor == nil {
                        presets
                    }
                }
                statsCard
                    .padding(.top, 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 146)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var totalSessions: Int { max(pomodoro.settings.sessionsBeforeLongBreak, 1) }

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

    /// Kartu statistik: menit hari ini & hari beruntun berdampingan, batang 7 hari di kanan.
    private var statsCard: some View {
        HStack(alignment: .bottom, spacing: 0) {
            statLine(minutesText(pomodoro.todayFocusMinutes), label: L("hari ini", "today"))
                .frame(minWidth: 64, alignment: .leading)
            statLine(Text("\(pomodoro.streakDays)") + Text(L(" hari", pomodoro.streakDays == 1 ? " day" : " days")).font(.system(size: 12, weight: .bold, design: .rounded)),
                     label: L("beruntun", "streak"))
                .padding(.leading, 14)
            Spacer(minLength: 10)
            WeekBars(minutes: pomodoro.weekMinutes, accent: accent, maxHeight: 34)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        // Kartu mengisi sisa tinggi kolom (sampai sejajar bawah cincin); isinya di tengah.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .surfaceCard()
    }

    private func minutesText(_ total: Int) -> Text {
        let unit = Font.system(size: 12, weight: .bold, design: .rounded)
        let h = total / 60, m = total % 60
        if h == 0 { return Text("\(m)") + Text(L(" mnt", " min")).font(unit) }
        return Text("\(h)") + Text(L(" j ", "h ")).font(unit) + Text("\(m)") + Text(L(" m", "m")).font(unit)
    }

    private func statLine(_ value: Text, label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            value
                .font(.system(size: 19, weight: .heavy, design: .rounded))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(style == .glass ? 0.72 : 0.55))
        }
    }
}

/// Batang menit fokus 7 hari; hari ini menyala dengan warna aksen.
struct WeekBars: View {
    let minutes: [Int]
    let accent: Color
    var maxHeight: CGFloat = 40
    @Environment(\.panelStyle) private var style

    var body: some View {
        let top = max(minutes.max() ?? 0, 25)
        let days = PomodoroCore.lastDays(minutes.count, endingAt: Date())
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(minutes.enumerated()), id: \.offset) { i, value in
                let today = i == minutes.count - 1
                VStack(spacing: 4) {
                    Capsule()
                        .fill(today
                              ? AnyShapeStyle(LinearGradient(colors: [accent.lighter(0.4), accent], startPoint: .top, endPoint: .bottom))
                              : AnyShapeStyle(Color.white.opacity(0.18)))
                        .frame(width: 9, height: max(4, maxHeight * CGFloat(value) / CGFloat(top)))
                    Text(i < days.count ? Self.initial(days[i]) : "")
                        .font(.system(size: 9.5, weight: today ? .bold : .medium))
                        .foregroundStyle(today ? accent.lighter(0.4) : .white.opacity(style == .glass ? 0.65 : 0.45))
                        .fixedSize()
                }
                .frame(width: 14)
                .help(L("\(value) menit", "\(value) min"))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Menit fokus 7 hari terakhir", "Focus minutes, last 7 days"))
        .accessibilityValue(minutes.map(String.init).joined(separator: ", "))
    }

    static func initial(_ date: Date) -> String {
        let wd = Calendar.current.component(.weekday, from: date) // 1 = Minggu
        let id = ["M", "S", "S", "R", "K", "J", "S"]
        let en = ["S", "M", "T", "W", "T", "F", "S"]
        return L(id[wd - 1], en[wd - 1])
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
