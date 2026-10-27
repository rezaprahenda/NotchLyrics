import AppKit
import SwiftUI
import Carbon.HIToolbox
import Combine

@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let player = PlayerMonitor()
    private let lyrics = LyricsStore()
    private let pomodoro = PomodoroModule()
    private let prayer = PrayerModule()
    private let shelf = ShelfModule()
    private let device = DeviceModule()
    private let mirror = MirrorModule()
    private let clipboard = ClipboardModule()
    private let lastfm = LastFMModule()
    private var controller: NotchController?
    private var statusItem: NSStatusItem?
    private let settingsWindow = SettingsWindowController()
    private var cancellables = Set<AnyCancellable>()

    // Menu ringkas
    private var focusItem: NSMenuItem?
    private var focusStopItem: NSMenuItem?
    private var compactLyricsItem: NSMenuItem?
    private var karaokeItem: NSMenuItem?
    private var sleepItem: NSMenuItem?
    private var sleepChoices: [NSMenuItem] = []
    private var chosenSleepMinutes = 0

    static func main() {
        let app = NSApplication.shared
        Migration.runIfNeeded() // sebelum AppDelegate membuat objek yang membaca pengaturan
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // tanpa ikon di Dock
        withExtendedLifetime(delegate) {
            app.run()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        lyrics.bind(to: player)
        lastfm.bind(to: player)
        let c = NotchController(player: player, lyrics: lyrics, pomodoro: pomodoro, prayer: prayer,
                                shelf: shelf, device: device, mirror: mirror,
                                clipboard: clipboard)
        controller = c
        c.show()
        player.start()
        setupStatusItem()
        // Shortcut ikut menyala / mati dari Pengaturan.
        c.vm.$shortcutsEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyShortcuts() }
            .store(in: &cancellables)
        startFaces()
        NotificationCenter.default.publisher(for: .popocuOpenSettings)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.openSettings() }
            .store(in: &cancellables)
    }

    // MARK: - Ekspresi ikon menu bar

    private var faceCancellable: AnyCancellable?
    private var currentFace: MenuFace?
    private var greeting = true

    /// Berkedip sekali saat dibuka, lalu ekspresi mengikuti keadaan app.
    private func startFaces() {
        guard let vm = controller?.vm else { return }
        setFace(.wink)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self else { return }
            self.greeting = false
            self.refreshFace(playing: self.player.isPlaying, peeking: vm.isPeeking,
                             sleepTimer: self.player.sleepUntil != nil || self.player.sleepAtTrackEnd,
                             focusing: self.pomodoro.isFocusRunning)
        }
        let music = Publishers.CombineLatest4(player.$isPlaying, vm.$isPeeking,
                                              player.$sleepUntil, player.$sleepAtTrackEnd)
        let focus = pomodoro.$phase.combineLatest(pomodoro.$pausedRemaining)
        faceCancellable = music.combineLatest(focus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] musicState, focusState in
                let (playing, peeking, until, atEnd) = musicState
                let (phase, paused) = focusState
                self?.refreshFace(playing: playing, peeking: peeking, sleepTimer: until != nil || atEnd,
                                  focusing: phase == .focus && paused == nil)
            }
    }

    private func refreshFace(playing: Bool, peeking: Bool, sleepTimer: Bool, focusing: Bool) {
        guard !greeting else { return }
        let face: MenuFace
        if peeking {
            face = .lookUp
        } else if focusing {
            face = .focus
        } else if sleepTimer || !playing {
            face = .sleep
        } else {
            face = .peek
        }
        setFace(face)
    }

    private func setFace(_ face: MenuFace) {
        guard face != currentFace else { return }
        currentFace = face
        statusItem?.button?.image = face.image
    }

    // MARK: - Shortcut keyboard

    /// ⌃⌥L lirik ringkas on/off · ⌃⌥[ / ⌃⌥] geser waktu lirik · ⌃⌥P pomodoro mulai/jeda.
    private func applyShortcuts() {
        HotKeyCenter.shared.unregisterAll()
        guard controller?.vm.shortcutsEnabled ?? true else { return }
        let mods = controlKey | optionKey
        HotKeyCenter.shared.register(keyCode: kVK_ANSI_L, modifiers: mods) { [weak self] in
            self?.toggleCompactLyrics()
        }
        HotKeyCenter.shared.register(keyCode: kVK_ANSI_LeftBracket, modifiers: mods) { [weak self] in
            self?.lyrics.adjustOffset(by: -0.5)
        }
        HotKeyCenter.shared.register(keyCode: kVK_ANSI_RightBracket, modifiers: mods) { [weak self] in
            self?.lyrics.adjustOffset(by: 0.5)
        }
        HotKeyCenter.shared.register(keyCode: kVK_ANSI_P, modifiers: mods) { [weak self] in
            self?.toggleFocus()
        }
    }

    // MARK: - Menu bar

    /// Menu bar hanya berisi aksi cepat; semua opsi ada di jendela Pengaturan.
    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = MenuFace.wink.image

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        let focus = NSMenuItem(title: "", action: #selector(toggleFocus), keyEquivalent: "")
        focus.target = self
        menu.addItem(focus)
        focusItem = focus

        let stop = NSMenuItem(title: L("Hentikan pomodoro", "Stop pomodoro"), action: #selector(stopFocus), keyEquivalent: "")
        stop.target = self
        stop.indentationLevel = 1
        menu.addItem(stop)
        focusStopItem = stop

        // Sleep timer
        let sleep = NSMenuItem(title: "Sleep timer", action: nil, keyEquivalent: "")
        let sleepMenu = NSMenu()
        sleepMenu.autoenablesItems = false
        // representedObject: 0 = mati, -1 = akhir lagu, >0 = menit
        for (title, minutes) in [(L("Mati", "Off"), 0), (L("15 menit", "15 minutes"), 15), (L("30 menit", "30 minutes"), 30),
                                 (L("45 menit", "45 minutes"), 45), (L("1 jam", "1 hour"), 60),
                                 (L("Sampai lagu ini selesai", "Until this song ends"), -1)] {
            let choice = NSMenuItem(title: title, action: #selector(setSleep(_:)), keyEquivalent: "")
            choice.target = self
            choice.representedObject = minutes
            sleepMenu.addItem(choice)
            sleepChoices.append(choice)
        }
        sleep.submenu = sleepMenu
        menu.addItem(sleep)
        sleepItem = sleep

        menu.addItem(.separator())

        let compact = NSMenuItem(title: L("Tampilkan lirik di mode ringkas", "Show lyrics in compact mode"),
                                 action: #selector(toggleCompactLyrics), keyEquivalent: "")
        compact.target = self
        menu.addItem(compact)
        compactLyricsItem = compact

        let karaoke = NSMenuItem(title: "Karaoke", action: #selector(toggleKaraoke), keyEquivalent: "")
        karaoke.target = self
        karaoke.indentationLevel = 1
        menu.addItem(karaoke)
        karaokeItem = karaoke

        menu.addItem(.separator())

        let settings = NSMenuItem(title: L("Pengaturan…", "Settings…"), action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: L("Keluar popocu", "Quit popocu"), action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
        refreshMenuState()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshMenuState()
    }

    private func refreshMenuState() {
        // Pomodoro
        let mins = pomodoro.settings.focusMinutes
        if pomodoro.isPaused {
            focusItem?.title = L("Lanjutkan pomodoro", "Resume pomodoro")
        } else if pomodoro.phase != .idle {
            focusItem?.title = L("Jeda pomodoro", "Pause pomodoro")
        } else if let next = pomodoro.waitingFor {
            focusItem?.title = next.isBreak ? L("Mulai istirahat", "Start break") : L("Mulai fokus lagi", "Focus again")
        } else {
            focusItem?.title = L("Mulai fokus (\(mins) menit)", "Start focus (\(mins) min)")
        }
        focusItem?.isHidden = !pomodoro.enabled
        focusStopItem?.isHidden = !pomodoro.enabled || !pomodoro.isActive

        // Lirik
        let compactOn = controller?.vm.showCompactLyrics ?? true
        compactLyricsItem?.state = compactOn ? .on : .off
        karaokeItem?.state = lyrics.karaokeEnabled ? .on : .off
        karaokeItem?.isEnabled = compactOn

        // Sleep timer: tandai pilihan aktif + tampilkan sisa waktu di judul.
        let activeSleep: Int
        if player.sleepAtTrackEnd {
            activeSleep = -1
            sleepItem?.title = L("Sleep timer · sampai lagu selesai", "Sleep timer · until song ends")
        } else if let until = player.sleepUntil {
            let minutes = max(1, Int((until.timeIntervalSinceNow / 60).rounded(.up)))
            activeSleep = chosenSleepMinutes
            sleepItem?.title = L("Sleep timer · sisa \(minutes) menit", "Sleep timer · \(minutes) min left")
        } else {
            activeSleep = 0
            sleepItem?.title = "Sleep timer"
        }
        for choice in sleepChoices {
            choice.state = (choice.representedObject as? Int) == activeSleep ? .on : .off
        }
    }

    // MARK: - Aksi

    @objc private func toggleFocus() {
        guard pomodoro.enabled else { return }
        pomodoro.togglePause()
        refreshMenuState()
    }

    @objc private func stopFocus() {
        pomodoro.stop()
        refreshMenuState()
    }

    @objc private func toggleCompactLyrics() {
        guard let vm = controller?.vm else { return }
        vm.showCompactLyrics.toggle()
        refreshMenuState()
    }

    @objc private func toggleKaraoke() {
        lyrics.karaokeEnabled.toggle()
        refreshMenuState()
    }

    @objc private func setSleep(_ sender: NSMenuItem) {
        guard let minutes = sender.representedObject as? Int else { return }
        chosenSleepMinutes = minutes
        switch minutes {
        case 0: player.cancelSleepTimer()
        case -1: player.setSleepAtTrackEnd()
        default: player.setSleepTimer(minutes: minutes)
        }
        refreshMenuState()
    }

    @objc private func openSettings() {
        guard let vm = controller?.vm else { return }
        settingsWindow.show(vm: vm, player: player, lyrics: lyrics, pomodoro: pomodoro, prayer: prayer,
                            shelf: shelf, device: device, mirror: mirror,
                            clipboard: clipboard, lastfm: lastfm)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
