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
    @Published var frontWindowFillsScreen = false
    @Published var lyricLineFaded = false
    @Published var lyricLineSuppressed = false
    /// Telinga (kiri: cover, kanan: equalizer) yang sedang disembunyikan karena kursor ada di
    /// menu bar di atasnya, supaya menu app (mis. "Server" di Tableau) terlihat dan bisa diklik.
    @Published var hiddenEar: EarSide?

    /// Warna equalizer & aksen mengikuti cover album (kalau tidak: warna app).
    @Published var accentFromArtwork: Bool = NotchViewModel.storedBool("accentFromArtwork", false) {
        didSet { UserDefaults.standard.set(accentFromArtwork, forKey: "accentFromArtwork") }
    }
    /// Notch tidak ikut terlihat di share screen, rekaman, dan screenshot.
    @Published var hideFromScreenCapture: Bool = NotchViewModel.storedBool("hideFromScreenCapture", false) {
        didSet { UserDefaults.standard.set(hideFromScreenCapture, forKey: "hideFromScreenCapture") }
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

    func mode(hasTrack: Bool) -> NotchMode {
        if isExpanded { return .expanded }
        if isPeeking && hasTrack { return .peek }
        if hasTrack { return .compact }
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
            return CGSize(width: max(baseWidth + earWidth * 2, 380),
                          height: notchSize.height + peekHeight)
        case .expanded:
            return CGSize(width: max(baseWidth + 220, 500),
                          height: notchSize.height + 214)
        }
    }

    func cornerRadius(for mode: NotchMode) -> CGFloat {
        switch mode {
        case .hidden, .idle: return 10
        case .compact: return 14
        case .peek: return 20
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
    private let player: PlayerMonitor
    private let lyrics: LyricsStore

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

    init(player: PlayerMonitor, lyrics: LyricsStore) {
        self.player = player
        self.lyrics = lyrics

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

        let root = NotchRootView(vm: vm, player: player, lyrics: lyrics)
        let host = FirstMouseHostingView(rootView: root)
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = host
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

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.reposition()
        }
    }

    /// Cari layar yang punya notch, hitung ukuran notch, taruh panel di tengah atas.
    private func reposition() {
        let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
            ?? NSScreen.main
            ?? NSScreen.screens.first
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
        let mode = vm.mode(hasTrack: player.track != nil)
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
        updateEars(mouse)
        let z = zones()

        var activeRect = z.full
        var faded = false
        if z.mode == .peek {
            // Notifikasi ganti lagu tembus klik; hanya strip setinggi menu bar yang interaktif.
            activeRect = NSRect(x: z.full.minX, y: panel.frame.maxY - vm.notchSize.height,
                                width: z.full.width, height: vm.notchSize.height)
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
        if let ear = vm.hiddenEar, columnRect(ear).contains(mouse) { inside = false }
        if panel.ignoresMouseEvents == inside {
            panel.ignoresMouseEvents = !inside
        }
        schedule(expand: inside)
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
        if vm.mode(hasTrack: player.track != nil) == .compact {
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

        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { vm.isPeeking = true }
        peekWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { self.vm.isPeeking = false }
        }
        peekWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: work)
    }

    /// Klik di zona baris lirik → sembunyikan liriknya beberapa detik (timer diulang tiap klik).
    private func handleClick() {
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
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (expand ? 0.12 : 0.3), execute: work)
    }
}
