import AppKit
import SwiftUI
import Combine

enum EarSide: Equatable {
    case left, right
}

enum NotchMode: Equatable {
    case hidden    // Mac tanpa notch & tidak ada musik
    case idle      // ukuran notch asli (tak terlihat)
    case compact   // ada musik: cover + equalizer + 1 baris lirik
    case peek      // sebentar setelah ganti lagu: judul + artis
    case expanded  // di-hover: lirik penuh + kontrol
}

final class NotchViewModel: ObservableObject {
    @Published var isExpanded = false
    @Published var notchSize = CGSize(width: 200, height: 32)
    @Published var hasNotch = true
    @Published var showCompactLyrics: Bool = NotchViewModel.storedBool("showCompactLyrics", true) {
        didSet { UserDefaults.standard.set(showCompactLyrics, forKey: "showCompactLyrics") }
    }
    /// Baris lirik di bawah notch tidak menangkap klik dan memudar saat kursor mendekat.
    @Published var lyricsClickThrough: Bool = NotchViewModel.storedBool("lyricsClickThrough", true) {
        didSet { UserDefaults.standard.set(lyricsClickThrough, forKey: "lyricsClickThrough") }
    }
    /// Sembunyikan baris lirik kalau jendela depan memenuhi lebar layar (full screen / maximize).
    @Published var hideLyricsWhenFullWindow: Bool = NotchViewModel.storedBool("hideLyricsWhenFullWindow", true) {
        didSet { UserDefaults.standard.set(hideLyricsWhenFullWindow, forKey: "hideLyricsWhenFullWindow") }
    }

    /// Setelah klik di area lirik, sembunyikan baris lirik selama N detik (0 = mati).
    @Published var hideAfterClickSeconds: Double = (UserDefaults.standard.object(forKey: "hideAfterClickSeconds") as? Double) ?? 5 {
        didSet { UserDefaults.standard.set(hideAfterClickSeconds, forKey: "hideAfterClickSeconds") }
    }

    /// Notch melebar sebentar menampilkan judul + artis saat lagu berganti.
    @Published var showTrackPeek: Bool = NotchViewModel.storedBool("showTrackPeek", true) {
        didSet { UserDefaults.standard.set(showTrackPeek, forKey: "showTrackPeek") }
    }

    /// Status runtime (tidak disimpan).
    @Published var isPeeking = false
    /// Peek yang sedang tampil (nil = tidak ada).
    @Published var activePeek: PeekEvent?
    /// Siapa yang memakai telinga notch (aturan ROADMAP §3), diisi oleh NotchController.
    @Published var earOwner: EarOwner = .none
    /// Halaman panel penuh yang terakhir dibuka.
    @Published var expandedPage: ExpandedPage =
        ExpandedPage(rawValue: UserDefaults.standard.string(forKey: "expandedPage") ?? "") ?? .music {
        didSet { UserDefaults.standard.set(expandedPage.rawValue, forKey: "expandedPage") }
    }
    /// Tutup peek yang sedang tampil (dipasang oleh NotchController, dipakai tombol di peek).
    var dismissPeek: (() -> Void)?
    @Published var frontWindowFillsScreen = false
    @Published var lyricLineFaded = false
    @Published var lyricLineSuppressed = false
    /// Telinga (kiri: cover, kanan: equalizer) yang sedang disembunyikan karena kursor ada di
    /// menu bar di atasnya, supaya menu app (mis. "Server" di Tableau) terlihat dan bisa diklik.
    @Published var hiddenEar: EarSide?

    /// Warna equalizer & aksen mengikuti cover album (kalau tidak: warna app).
    @Published var panelStyle: PanelStyle =
        PanelStyle(rawValue: UserDefaults.standard.string(forKey: "panelStyle") ?? "") ?? .vivid {
        didSet { UserDefaults.standard.set(panelStyle.rawValue, forKey: "panelStyle") }
    }
    @Published var accentFromArtwork: Bool = NotchViewModel.storedBool("accentFromArtwork", false) {
        didSet { UserDefaults.standard.set(accentFromArtwork, forKey: "accentFromArtwork") }
    }
    /// Notch tidak ikut terlihat di share screen, rekaman, dan screenshot.
    @Published var hideFromScreenCapture: Bool = NotchViewModel.storedBool("hideFromScreenCapture", false) {
        didSet { UserDefaults.standard.set(hideFromScreenCapture, forKey: "hideFromScreenCapture") }
    }
    /// Peek yang tidak penting (ganti lagu, perangkat, pengingat) diam saat mode Focus aktif.
    @Published var respectFocus: Bool = NotchViewModel.storedBool("respectFocus", true) {
        didSet {
            UserDefaults.standard.set(respectFocus, forKey: "respectFocus")
            if respectFocus { FocusStatus.requestAuthorizationIfNeeded() }
        }
    }
    @Published var displayPreference: DisplayPreference =
        DisplayPreference(rawValue: UserDefaults.standard.string(forKey: "displayPreference") ?? "") ?? .automatic {
        didSet { UserDefaults.standard.set(displayPreference.rawValue, forKey: "displayPreference") }
    }
    /// Shortcut keyboard global (⌃⌥L, ⌃⌥[, ⌃⌥]).
    @Published var shortcutsEnabled: Bool = NotchViewModel.storedBool("shortcutsEnabled", true) {
        didSet { UserDefaults.standard.set(shortcutsEnabled, forKey: "shortcutsEnabled") }
    }

    func accent(for player: PlayerMonitor) -> Color {
        if accentFromArtwork, let color = player.artworkColor { return color }
        return player.track?.source.tint ?? .white
    }

    private static func storedBool(_ key: String, _ defaultValue: Bool) -> Bool {
        (UserDefaults.standard.object(forKey: key) as? Bool) ?? defaultValue
    }

    static let windowSize = CGSize(width: 640, height: 320)
    let earWidth: CGFloat = 70
    let compactLyricHeight: CGFloat = 30
    let compactDoubleLyricHeight: CGFloat = 46
    let peekHeight: CGFloat = 50

    var baseWidth: CGFloat { hasNotch ? notchSize.width : 180 }

    func mode() -> NotchMode {
        if isExpanded { return .expanded }
        if activePeek != nil { return .peek }
        if earOwner != .none { return .compact }
        return hasNotch ? .idle : .hidden
    }

    /// `ignoringSuppression`: dipakai untuk menghitung zona klik selama lirik sedang disembunyikan.
    func showsLyricLine(_ state: LyricsState, ignoringSuppression: Bool = false) -> Bool {
        showCompactLyrics
            && state.syncedLines != nil
            && !(hideLyricsWhenFullWindow && frontWindowFillsScreen)
            && (ignoringSuppression || !lyricLineSuppressed)
    }

    func size(for mode: NotchMode, showsLyricLine: Bool, doubleLine: Bool = false) -> CGSize {
        switch mode {
        case .hidden:
            return CGSize(width: baseWidth, height: notchSize.height)
        case .idle:
            return notchSize
        case .compact:
            return CGSize(width: baseWidth + earWidth * 2,
                          height: notchSize.height
                            + (showsLyricLine ? (doubleLine ? compactDoubleLyricHeight : compactLyricHeight) : 0))
        case .peek:
            if activePeek?.compact == true {
                return CGSize(width: baseWidth + earWidth * 2, height: notchSize.height)
            }
            return CGSize(width: max(baseWidth + earWidth * 2, 380),
                          height: notchSize.height + peekHeight)
        case .expanded:
            return CGSize(width: max(baseWidth + 220, 500),
                          height: notchSize.height + 244)
        }
    }

    func cornerRadius(for mode: NotchMode) -> CGFloat {
        switch mode {
        case .hidden, .idle: return 10
        case .compact: return 14
        case .peek: return activePeek?.compact == true ? 14 : 20
        case .expanded: return 26
        }
    }
}

/// Panel transparan di atas menu bar. Tidak pernah jadi key window,
/// jadi tidak mencuri fokus keyboard dari app lain.
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Supaya klik pertama di tombol langsung bekerja walau app tidak aktif.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class NotchController {
    let vm = NotchViewModel()
    private let panel: NotchPanel
    /// Kaca untuk gaya "Kaca": NSVisualEffectView biasa di bawah SwiftUI (bukan di dalamnya),
    /// supaya macOS benar-benar bisa memburamkan isi layar di belakang jendela.
    private let glass = GlassView()
    private var glassCancellables = Set<AnyCancellable>()
    private var glassRadius: CGFloat = -1
    private var glassSize: CGSize = .zero
    private let player: PlayerMonitor
    private let lyrics: LyricsStore
    private let pomodoro: PomodoroModule
    private let prayer: PrayerModule
    private let shelf: ShelfModule
    private let device: DeviceModule
    private let mirror: MirrorModule
    private let clipboard: ClipboardModule
    /// changeCount papan seret saat tombol mouse ditekan; berubah = sedang menyeret sesuatu.
    private var dragStartChangeCount = NSPasteboard(name: .drag).changeCount

    private var monitors: [Any] = []
    private var hoverTimer: Timer?
    private var pending: DispatchWorkItem?
    private var pendingExpand: Bool?
    private var screenObserver: NSObjectProtocol?
    private var windowTimer: Timer?
    private weak var currentScreen: NSScreen?
    private var unsuppressWork: DispatchWorkItem?
    private var peekWork: DispatchWorkItem?
    private var lastTrackKey: String?
    private var trackCancellable: AnyCancellable?
    private var captureCancellable: AnyCancellable?
    private var ownerCancellables = Set<AnyCancellable>()
    private var peekQueue = PeekQueue()
    /// Kapan musik di-pause (untuk aturan "pause lama turun prioritas").
    private var pausedAt: Date?
    private var ownerRefreshWork: DispatchWorkItem?
    /// Musik di-pause oleh pomodoro (bukan oleh pengguna) → boleh dilanjutkan otomatis.
    private var pausedByPomodoro = false

    init(player: PlayerMonitor, lyrics: LyricsStore, pomodoro: PomodoroModule, prayer: PrayerModule,
         shelf: ShelfModule, device: DeviceModule, mirror: MirrorModule,
         clipboard: ClipboardModule) {
        self.player = player
        self.lyrics = lyrics
        self.pomodoro = pomodoro
        self.prayer = prayer
        self.shelf = shelf
        self.device = device
        self.mirror = mirror
        self.clipboard = clipboard

        let size = NotchViewModel.windowSize
        panel = NotchPanel(contentRect: NSRect(origin: .zero, size: size),
                           styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered,
                           defer: false)
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = true

        let root = NotchRootView(vm: vm, player: player, lyrics: lyrics, pomodoro: pomodoro, prayer: prayer, shelf: shelf,
                                 mirror: mirror, clipboard: clipboard)
        let host = FirstMouseHostingView(rootView: root)
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.addSubview(glass)
        container.addSubview(host)
        panel.contentView = container

        // Ikuti setiap perubahan tampilan (mode, ukuran, gaya, baris lirik).
        let refresh: () -> Void = { [weak self] in DispatchQueue.main.async { self?.updateGlass() } }
        vm.objectWillChange.sink { _ in refresh() }.store(in: &glassCancellables)
        lyrics.objectWillChange.sink { _ in refresh() }.store(in: &glassCancellables)
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
            .sink { _ in refresh() }.store(in: &glassCancellables)
    }

    /// Posisikan kaca tepat di belakang bagian notch yang turun di bawah menu bar.
    private func updateGlass() {
        let mode = vm.mode()
        let showLine = vm.showsLyricLine(lyrics.state)
        let size = vm.size(for: mode, showsLyricLine: showLine, doubleLine: lyrics.compactIsDouble)
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let visible = vm.panelStyle == .glass && !reduce
            && mode != .hidden && mode != .idle
            && !(mode == .peek && vm.activePeek?.compact == true)
            && size.height > vm.notchSize.height + 1
            && !(mode == .compact && vm.lyricLineFaded)

        let leftCut: CGFloat = (mode == .compact && vm.hiddenEar == .left) ? vm.earWidth : 0
        let rightCut: CGFloat = (mode == .compact && vm.hiddenEar == .right) ? vm.earWidth : 0
        let window = NotchViewModel.windowSize
        let target = NSRect(x: (window.width - size.width) / 2 + leftCut,
                            y: window.height - size.height,
                            width: max(size.width - leftCut - rightCut, 0),
                            height: size.height)

        let radius = vm.cornerRadius(for: mode)
        if radius != glassRadius || target.size != glassSize {
            glassRadius = radius
            glassSize = target.size
            glass.maskImage = GlassView.mask(size: target.size, radius: radius)
        }
        let wasHidden = glass.alphaValue < 0.01
        if wasHidden { glass.frame = target }
        NSAnimationContext.runAnimationGroup { ctx in
            // Mendekati pegas SwiftUI (response 0,4) supaya kaca ikut membesar/mengecil bersama panel.
            ctx.duration = 0.32
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
            glass.animator().frame = target
            glass.animator().alphaValue = visible ? 1 : 0
        }
    }

    func show() {
        reposition()
        panel.orderFrontRegardless()

        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] _ in
            self?.updateHover()
        }) {
            monitors.append(m)
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] event in
            self?.updateHover()
            return event
        }) {
            monitors.append(m)
        }

        // Klik yang tembus ke app lain (mis. address bar browser) ditangkap di sini.
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            self?.handleClick()
        }) {
            monitors.append(m)
        }

        // Cadangan untuk kasus event mouse terlewat atau ukuran berubah karena lagu ganti.
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateHover()
        }
        RunLoop.main.add(t, forMode: .common)
        hoverTimer = t

        // Cek tiap detik apakah jendela depan memenuhi layar.
        let w = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkFrontWindow()
        }
        RunLoop.main.add(w, forMode: .common)
        windowTimer = w
        checkFrontWindow()

        // Notifikasi ganti lagu.
        // Disembunyikan dari share screen / rekaman / screenshot kalau opsinya aktif.
        captureCancellable = vm.$hideFromScreenCapture
            .sink { [weak self] hide in self?.panel.sharingType = hide ? .none : .readOnly }

        trackCancellable = player.$track
            .removeDuplicates()
            .sink { [weak self] track in self?.trackChanged(track) }

        startCoordinator()

        vm.$displayPreference
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reposition() }
            .store(in: &ownerCancellables)
        if vm.respectFocus { FocusStatus.requestAuthorizationIfNeeded() }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.reposition()
        }
    }

    /// Cari layar yang punya notch, hitung ukuran notch, taruh panel di tengah atas.
    private func reposition() {
        let notched = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
        let primary = NSScreen.screens.first // layar dengan menu bar utama
        let screen = vm.displayPreference == .automatic ? (notched ?? primary ?? NSScreen.main) : (primary ?? NSScreen.main)
        guard let screen else { return }
        currentScreen = screen

        let top = screen.safeAreaInsets.top
        if top > 0, let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            vm.hasNotch = true
            vm.notchSize = CGSize(width: screen.frame.width - l.width - r.width, height: top)
        } else {
            vm.hasNotch = false
            let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
            vm.notchSize = CGSize(width: 180, height: max(menuBar, 24))
        }

        let s = NotchViewModel.windowSize
        panel.setFrame(NSRect(x: screen.frame.midX - s.width / 2,
                              y: screen.frame.maxY - s.height,
                              width: s.width, height: s.height),
                       display: true)
    }

    /// Panel hanya menangkap mouse di area hitam; sisanya tembus ke menu bar / app di bawahnya.
    /// Area notch saat ini: rect penuh, plus (kalau baris lirik tembus klik aktif)
    /// strip setinggi menu bar dan zona baris lirik di bawahnya.
    private func zones(ignoringSuppression: Bool = false) -> (mode: NotchMode, full: NSRect, strip: NSRect?, lineZone: NSRect?) {
        let mode = vm.mode()
        let showLine = vm.showsLyricLine(lyrics.state, ignoringSuppression: ignoringSuppression)
        let size = vm.size(for: mode, showsLyricLine: showLine, doubleLine: lyrics.compactIsDouble)
        let f = panel.frame
        let full = NSRect(x: f.midX - size.width / 2, y: f.maxY - size.height,
                          width: size.width, height: size.height)
        guard mode == .compact, showLine, vm.lyricsClickThrough else {
            return (mode, full, nil, nil)
        }
        let strip = NSRect(x: full.minX, y: f.maxY - vm.notchSize.height,
                           width: full.width, height: vm.notchSize.height)
        let line = NSRect(x: full.minX, y: full.minY,
                          width: full.width, height: full.height - vm.notchSize.height)
        return (mode, full, strip, line.insetBy(dx: -24, dy: -24))
    }

    private func updateHover() {
        let mouse = NSEvent.mouseLocation
        checkFileDrag(mouse)
        updateEars(mouse)
        let z = zones()

        var activeRect = z.full
        var faded = false
        var expandAllowed = true
        if z.mode == .peek {
            // Peek tembus klik; hanya strip setinggi menu bar yang interaktif...
            let strip = NSRect(x: z.full.minX, y: panel.frame.maxY - vm.notchSize.height,
                               width: z.full.width, height: vm.notchSize.height)
            if peekHasButtons {
                // ...kecuali peek yang punya tombol: bisa diklik, tapi tidak membuka panel penuh.
                activeRect = z.full
                expandAllowed = strip.insetBy(dx: -4, dy: -4).contains(mouse)
            } else {
                activeRect = strip
            }
        } else if let strip = z.strip, let lineZone = z.lineZone {
            // Hanya strip setinggi notch/menu bar yang interaktif; baris lirik di bawahnya tembus klik.
            activeRect = strip
            faded = lineZone.contains(mouse) && !strip.contains(mouse)
        }
        let mode = z.mode

        if vm.lyricLineFaded != faded {
            withAnimation(.easeOut(duration: 0.2)) { vm.lyricLineFaded = faded }
        }

        var inside = mode != .hidden && activeRect.insetBy(dx: -4, dy: -4).contains(mouse)
        // Di mode ringkas, area telinga (dan sisi yang sedang disembunyikan) hanya untuk
        // menyingkirkan sisi itu; jangan sampai membuka panel penuh. Pemicu buka panel
        // berjeda 0,12 detik, lebih cepat dari jeda sembunyi sisi (0,15), jadi harus
        // dicegah di sini, bukan menunggu `hiddenEar` terisi.
        if mode == .compact {
            if earRect(.left).contains(mouse) || earRect(.right).contains(mouse) { inside = false }
            if let ear = vm.hiddenEar, columnRect(ear).contains(mouse) { inside = false }
        }
        if panel.ignoresMouseEvents == inside {
            panel.ignoresMouseEvents = !inside
        }
        schedule(expand: inside && expandAllowed)
    }

    /// Area telinga di menu bar (koordinat layar): pemicu menyembunyikan sisi itu.
    private func earRect(_ side: EarSide) -> NSRect {
        let column = columnRect(side)
        let bar = vm.notchSize.height
        return NSRect(x: column.minX, y: column.maxY - bar, width: column.width, height: bar + 1)
    }

    /// Seluruh kolom sisi itu (telinga + bagian baris lirik di bawahnya), dihitung dari ukuran
    /// mode ringkas penuh, jadi tetap sama walau sisinya sedang disembunyikan.
    private func columnRect(_ side: EarSide) -> NSRect {
        let f = panel.frame
        let showLine = vm.showsLyricLine(lyrics.state)
        let size = vm.size(for: .compact, showsLyricLine: showLine, doubleLine: lyrics.compactIsDouble)
        let left = f.midX - size.width / 2
        switch side {
        case .left:
            return NSRect(x: left - 8, y: f.maxY - size.height, width: vm.earWidth + 8, height: size.height + 1)
        case .right:
            return NSRect(x: f.midX + vm.baseWidth / 2, y: f.maxY - size.height,
                          width: vm.earWidth + 8, height: size.height + 1)
        }
    }

    private var earWork: DispatchWorkItem?
    private var pendingEar: EarSide??

    /// Sembunyikan sisi yang telinganya didekati kursor; tetap tersembunyi selama kursor masih
    /// di kolom sisi itu. Ada jeda kecil supaya tidak kedip saat kursor cuma lewat.
    private func updateEars(_ mouse: NSPoint) {
        var side: EarSide?
        if vm.mode() == .compact {
            if let current = vm.hiddenEar, columnRect(current).contains(mouse) {
                side = current
            } else if earRect(.left).contains(mouse) {
                side = .left
            } else if earRect(.right).contains(mouse) {
                side = .right
            }
        }
        guard vm.hiddenEar != side else {
            earWork?.cancel()
            earWork = nil
            pendingEar = nil
            return
        }
        if let pending = pendingEar, pending == side { return }
        earWork?.cancel()
        pendingEar = .some(side)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { self.vm.hiddenEar = side }
            self.earWork = nil
            self.pendingEar = nil
        }
        earWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (side == nil ? 0.25 : 0.15), execute: work)
    }

    /// Tampilkan judul + artis sebentar saat lagu berganti (tidak saat app baru dibuka).
    private func trackChanged(_ track: Track?) {
        let previous = lastTrackKey
        lastTrackKey = track?.key
        guard vm.showTrackPeek,
              let track, let previous, previous != track.key,
              !vm.isExpanded
        else { return }
        post(PeekEvent(kind: .trackChange, id: track.key, createdAt: Date(),
                       title: track.title, subtitle: track.artist))
    }

    // MARK: - Koordinator: pemilik telinga & peek

    private func startCoordinator() {
        vm.dismissPeek = { [weak self] in self?.dismissPeek() }
        pomodoro.onEvent = { [weak self] event in self?.handlePomodoro(event) }
        prayer.onEvent = { [weak self] event in self?.handlePrayer(event) }
        device.onPeek = { [weak self] event in self?.post(event) }
        device.start()

        player.$isPlaying
            .removeDuplicates()
            .sink { [weak self] playing in
                guard let self else { return }
                self.pausedAt = playing ? nil : (self.pausedAt ?? Date())
            }
            .store(in: &ownerCancellables)

        // Semua masukan aturan prioritas → hitung ulang pemilik telinga.
        Publishers.Merge4(player.$track.map { _ in () },
                          player.$isPlaying.map { _ in () },
                          pomodoro.$phase.map { _ in () },
                          pomodoro.$waitingFor.map { _ in () })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.refreshOwner() }
            .store(in: &ownerCancellables)

        Publishers.Merge5(prayer.$now.map { _ in () },
                          prayer.$today.map { _ in () },
                          prayer.$enabled.map { _ in () },
                          shelf.$items.map { _ in () },
                          shelf.$enabled.map { _ in () })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.refreshOwner() }
            .store(in: &ownerCancellables)
    }

    private func refreshOwner() {
        var s = NotchSituation()
        s.hasTrack = player.track != nil
        s.isPlaying = player.isPlaying
        s.pausedFor = pausedAt.map { Date().timeIntervalSince($0) } ?? 0
        s.pomodoroRunning = pomodoro.isActive
        s.shelfItems = shelf.enabled ? shelf.items.count : 0
        if prayer.enabled {
            let now = Date()
            s.minutesSincePrayer = prayer.minutesSinceLast(at: now)
            s.minutesToPrayer = prayer.minutesToNext(at: now)
            // Mode Ramadan: hitung mundur berbuka tampil satu jam sebelum Maghrib.
            if prayer.isRamadan, prayer.next(after: now)?.prayer == .maghrib,
               let to = s.minutesToPrayer, to <= 60 {
                s.minutesToPrayer = min(to, NotchPriority.prayerSoonWindow - 1)
            }
        }
        let owner = NotchPriority.earOwner(s)
        if vm.earOwner != owner {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) { vm.earOwner = owner }
        }
        // Musik yang di-pause turun prioritas setelah 1 menit: hitung ulang saat itu.
        ownerRefreshWork?.cancel()
        if let pausedAt, s.hasTrack, !s.isPlaying {
            let wait = NotchPriority.musicIdleAfter - Date().timeIntervalSince(pausedAt) + 0.5
            if wait > 0 {
                let work = DispatchWorkItem { [weak self] in self?.refreshOwner() }
                ownerRefreshWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: work)
            }
        }
    }

    /// Masukkan peek ke antrian; tampil kalau tidak ada peek lain.
    func post(_ event: PeekEvent) {
        // Mode Focus: hanya peek penting (salat, pomodoro) yang tetap muncul.
        if vm.respectFocus, [.trackChange, .device, .reminder].contains(event.kind), FocusStatus.isFocused {
            return
        }
        peekQueue.push(event)
        presentNextPeek()
    }

    private func presentNextPeek() {
        guard vm.activePeek == nil, !vm.isExpanded, let event = peekQueue.next() else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            vm.activePeek = event
            vm.isPeeking = true
        }
        schedulePeekEnd(after: event.kind.duration)
    }

    private func schedulePeekEnd(after seconds: TimeInterval) {
        peekWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Peek dengan tombol tetap terbuka selama kursor di atasnya.
            if self.peekHasButtons, self.zones().full.contains(NSEvent.mouseLocation) {
                self.schedulePeekEnd(after: 2)
                return
            }
            self.dismissPeek()
        }
        peekWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    /// Peek pomodoro & adzan punya tombol, jadi harus bisa diklik.
    private var peekHasButtons: Bool {
        switch vm.activePeek?.kind {
        case .pomodoro?: return true
        case .prayer?: return prayer.adhanSound != .off
        default: return false
        }
    }

    private func dismissPeek() {
        peekWork?.cancel()
        peekWork = nil
        guard vm.activePeek != nil else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            vm.activePeek = nil
            vm.isPeeking = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.presentNextPeek() }
    }

    // MARK: - Pomodoro

    private func handlePomodoro(_ event: PomodoroEvent) {
        switch event {
        case .phaseStarted(let phase):
            applyMusicPolicy(for: phase)
        case .phaseEnded(let finished, let next):
            let minutes = Int(PomodoroCore.duration(of: next, settings: pomodoro.settings) / 60)
            let total = pomodoro.settings.sessionsBeforeLongBreak
            let title = finished == .focus
                ? L("Fokus selesai — sesi \(max(pomodoro.cycleFocusDone, 1)) dari \(total)",
                    "Focus done — session \(max(pomodoro.cycleFocusDone, 1)) of \(total)")
                : L("Istirahat selesai", "Break's over")
            let subtitle = next.isBreak
                ? L("Istirahat \(minutes) menit", "\(minutes)-minute break")
                : L("Lanjut fokus \(minutes) menit", "Focus for \(minutes) minutes")
            NSSound(named: "Glass")?.play()
            post(PeekEvent(kind: .pomodoro, id: "pomodoro", createdAt: Date(), title: title, subtitle: subtitle))
        case .reminder(let title, let subtitle):
            post(PeekEvent(kind: .reminder, id: title, createdAt: Date(), title: title, subtitle: subtitle))
        }
    }

    // MARK: - Salat

    private func handlePrayer(_ event: PrayerEvent) {
        switch event {
        case .arrived(.imsak):
            post(PeekEvent(kind: .prayer, id: "imsak", createdAt: Date(), title: "Imsak",
                           subtitle: L("Waktunya berhenti sahur", "Time to stop eating")))
        case .arrived(let p):
            var notes: [String] = []
            if !prayer.placeName.isEmpty { notes.append(prayer.placeName) }
            if prayer.pausePomodoroAtAdhan, pomodoro.phase != .idle, !pomodoro.isPaused {
                pomodoro.pause()
                notes.append(L("pomodoro dijeda", "pomodoro paused"))
            }
            if prayer.pauseMusicAtAdhan, player.isPlaying {
                player.pause()
                notes.append(L("musik dijeda", "music paused"))
            }
            let title = p == .maghrib && prayer.isRamadan
                ? L("Waktu Maghrib — selamat berbuka", "Maghrib — time to break the fast")
                : L("Waktu \(p.title)", "\(p.title) time")
            post(PeekEvent(kind: .prayer, id: p.rawValue, createdAt: Date(), title: title,
                           subtitle: notes.joined(separator: " · ")))
        case .upcoming(let p, let minutes):
            // Tanpa musik, hitung mundur sudah tampil di telinga; peek hanya saat musik diputar.
            guard player.isPlaying else { return }
            post(PeekEvent(kind: .reminder, id: "pre-\(p.rawValue)", createdAt: Date(),
                           title: L("\(p.title) \(minutes) menit lagi", "\(p.title) in \(minutes) minutes"),
                           subtitle: prayer.placeName))
        }
    }

    private func applyMusicPolicy(for phase: PomodoroPhase) {
        let shouldPause: Bool
        switch pomodoro.musicPolicy {
        case .untouched: return
        case .pauseOnBreak: shouldPause = phase.isBreak
        case .pauseOnFocus: shouldPause = phase == .focus
        }
        if shouldPause {
            if player.isPlaying {
                player.pause()
                pausedByPomodoro = true
            }
        } else if pausedByPomodoro {
            player.play()
            pausedByPomodoro = false
        }
    }

    /// Klik di zona baris lirik → sembunyikan liriknya beberapa detik (timer diulang tiap klik).
    /// File diseret mendekati notch → buka panel penuh di halaman Rak sebagai target drop.
    private func checkFileDrag(_ mouse: NSPoint) {
        guard shelf.enabled, !vm.isExpanded, NSEvent.pressedMouseButtons & 1 != 0 else { return }
        let pasteboard = NSPasteboard(name: .drag)
        guard pasteboard.changeCount != dragStartChangeCount,
              pasteboard.types?.contains(.fileURL) == true else { return }
        let f = panel.frame
        let zone = NSRect(x: f.midX - 220, y: f.maxY - vm.notchSize.height - 50,
                          width: 440, height: vm.notchSize.height + 50)
        guard zone.contains(mouse) else { return }
        pending?.cancel()
        pending = nil
        pendingExpand = nil
        vm.expandedPage = .shelf
        dismissPeek()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { vm.isExpanded = true }
        panel.ignoresMouseEvents = false
    }

    private func handleClick() {
        dragStartChangeCount = NSPasteboard(name: .drag).changeCount
        let seconds = vm.hideAfterClickSeconds
        guard seconds > 0 else { return }
        // Pakai zona baris lirik walau sedang disembunyikan, supaya klik berikutnya
        // di area yang sama tetap memperpanjang waktunya.
        let z = zones(ignoringSuppression: true)
        let mouse = NSEvent.mouseLocation
        guard let strip = z.strip, let lineZone = z.lineZone,
              lineZone.contains(mouse), !strip.contains(mouse)
        else { return }

        if !vm.lyricLineSuppressed {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { vm.lyricLineSuppressed = true }
        }
        unsuppressWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { self.vm.lyricLineSuppressed = false }
        }
        unsuppressWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func checkFrontWindow() {
        let fills = Self.frontWindowFillsScreen(currentScreen, menuBarHeight: vm.notchSize.height)
        if vm.frontWindowFillsScreen != fills {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                vm.frontWindowFillsScreen = fills
            }
        }
    }

    /// True kalau jendela paling depan dari app aktif selebar layar dan menempel di bawah menu bar
    /// (full screen atau di-maximize), sehingga baris lirik akan menutupi bagian atasnya.
    private static func frontWindowFillsScreen(_ screen: NSScreen?, menuBarHeight: CGFloat) -> Bool {
        guard let screen,
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]]
        else { return false }

        let pid = app.processIdentifier
        for info in list {
            guard (info[kCGWindowOwnerPID as String] as? Int).map({ pid_t($0) }) == pid,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary)
            else { continue }
            // Daftar urut dari depan ke belakang: jendela pertama milik app aktif = jendela depannya.
            return abs(rect.width - screen.frame.width) < 2 && rect.minY <= menuBarHeight + 2
        }
        return false
    }

    /// Sedikit jeda supaya notch tidak "kedip" saat kursor cuma lewat.
    private func schedule(expand: Bool) {
        if expand == vm.isExpanded {
            pending?.cancel()
            pending = nil
            pendingExpand = nil
            return
        }
        if pendingExpand == expand { return }

        pending?.cancel()
        pendingExpand = expand
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                self.vm.isExpanded = expand
            }
            self.pending = nil
            self.pendingExpand = nil
            if expand {
                self.dismissPeek()
            } else {
                self.presentNextPeek()
            }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (expand ? 0.12 : 0.3), execute: work)
    }
}
