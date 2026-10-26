import AppKit
import SwiftUI
import ServiceManagement
import Carbon.HIToolbox
import Combine

@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let player = PlayerMonitor()
    private let lyrics = LyricsStore()
    private var controller: NotchController?
    private var statusItem: NSStatusItem?
    private var compactLyricsItem: NSMenuItem?
    private var clickThroughItem: NSMenuItem?
    private var fullWindowItem: NSMenuItem?
    private var hideAfterClickItem: NSMenuItem?
    private var hideAfterClickChoices: [NSMenuItem] = []
    private var loginItem: NSMenuItem?
    private var peekItem: NSMenuItem?
    private var compactStyleItem: NSMenuItem?
    private var compactStyleChoices: [NSMenuItem] = []
    private var sleepItem: NSMenuItem?
    private var sleepChoices: [NSMenuItem] = []
    private var chosenSleepMinutes = 0
    private var autoPauseItem: NSMenuItem?
    private var targetChoices: [NSMenuItem] = []
    private var karaokeItem: NSMenuItem?
    private var accentItem: NSMenuItem?
    private var captureItem: NSMenuItem?
    private var shortcutsItem: NSMenuItem?
    private var languageChoices: [NSMenuItem] = []

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
        let c = NotchController(player: player, lyrics: lyrics)
        controller = c
        c.show()
        player.start()
        setupStatusItem()
        applyShortcuts()
        startFaces()
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
                             sleepTimer: self.player.sleepUntil != nil || self.player.sleepAtTrackEnd)
        }
        faceCancellable = Publishers.CombineLatest4(player.$isPlaying, vm.$isPeeking,
                                                    player.$sleepUntil, player.$sleepAtTrackEnd)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] playing, peeking, until, atEnd in
                self?.refreshFace(playing: playing, peeking: peeking, sleepTimer: until != nil || atEnd)
            }
    }

    private func refreshFace(playing: Bool, peeking: Bool, sleepTimer: Bool) {
        guard !greeting else { return }
        let face: MenuFace
        if peeking {
            face = .lookUp
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

    /// ⌃⌥L lirik ringkas on/off · ⌃⌥[ lirik lebih lambat · ⌃⌥] lirik lebih cepat.
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
    }

    // Ikon kecil di menu bar: pengaturan + tombol keluar
    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = MenuFace.wink.image

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false // supaya isEnabled manual di bawah dihormati

        let toggle = NSMenuItem(title: L("Tampilkan lirik di mode ringkas", "Show lyrics in compact mode"),
                                action: #selector(toggleCompactLyrics),
                                keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)

        // Isi baris lirik ringkas: asli / latin / terjemahan / latin + terjemahan
        let styleItem = NSMenuItem(title: L("Isi baris lirik", "Lyric line content"), action: nil, keyEquivalent: "")
        styleItem.indentationLevel = 1
        let styleMenu = NSMenu()
        styleMenu.autoenablesItems = false
        for style in CompactLyricStyle.allCases {
            let choice = NSMenuItem(title: style.title, action: #selector(setCompactStyle(_:)), keyEquivalent: "")
            choice.target = self
            choice.representedObject = style.rawValue
            styleMenu.addItem(choice)
            compactStyleChoices.append(choice)
        }
        styleItem.submenu = styleMenu
        menu.addItem(styleItem)
        compactStyleItem = styleItem

        let karaoke = NSMenuItem(title: L("Karaoke (baris terisi mengikuti lagu)", "Karaoke (lines fill as they are sung)"),
                                 action: #selector(toggleKaraoke), keyEquivalent: "")
        karaoke.target = self
        karaoke.indentationLevel = 1
        menu.addItem(karaoke)
        karaokeItem = karaoke

        let clickThrough = NSMenuItem(title: L("Lirik tembus klik & memudar saat didekati", "Click-through lyrics that fade on approach"),
                                      action: #selector(toggleClickThrough),
                                      keyEquivalent: "")
        clickThrough.target = self
        clickThrough.indentationLevel = 1
        menu.addItem(clickThrough)

        let hideAfterClick = NSMenuItem(title: L("Sembunyikan lirik setelah diklik", "Hide lyrics after clicking"), action: nil, keyEquivalent: "")
        hideAfterClick.indentationLevel = 1
        let sub = NSMenu()
        sub.autoenablesItems = false
        for (title, seconds) in [(L("Mati", "Off"), 0.0), (L("3 detik", "3 seconds"), 3.0), (L("5 detik", "5 seconds"), 5.0), (L("10 detik", "10 seconds"), 10.0)] {
            let choice = NSMenuItem(title: title, action: #selector(setHideAfterClick(_:)), keyEquivalent: "")
            choice.target = self
            choice.representedObject = seconds
            sub.addItem(choice)
            hideAfterClickChoices.append(choice)
        }
        hideAfterClick.submenu = sub
        menu.addItem(hideAfterClick)

        let fullWindow = NSMenuItem(title: L("Sembunyikan lirik saat jendela memenuhi layar", "Hide lyrics when a window fills the screen"),
                                    action: #selector(toggleFullWindow),
                                    keyEquivalent: "")
        fullWindow.target = self
        fullWindow.indentationLevel = 1
        menu.addItem(fullWindow)

        let peek = NSMenuItem(title: L("Notifikasi ganti lagu", "Track change banner"),
                              action: #selector(togglePeek),
                              keyEquivalent: "")
        peek.target = self
        menu.addItem(peek)
        peekItem = peek

        let accent = NSMenuItem(title: L("Warna mengikuti cover album", "Match colors to album art"),
                                action: #selector(toggleAccent), keyEquivalent: "")
        accent.target = self
        menu.addItem(accent)
        accentItem = accent

        let capture = NSMenuItem(title: L("Sembunyikan saat share screen & rekam layar", "Hide during screen sharing & recording"),
                                 action: #selector(toggleCapture), keyEquivalent: "")
        capture.target = self
        menu.addItem(capture)
        captureItem = capture

        let shortcuts = NSMenuItem(title: L("Shortcut keyboard (⌃⌥L, ⌃⌥[ ⌃⌥])", "Keyboard shortcuts (⌃⌥L, ⌃⌥[ ⌃⌥])"),
                                   action: #selector(toggleShortcuts), keyEquivalent: "")
        shortcuts.target = self
        shortcuts.toolTip = L("⌃⌥L: lirik ringkas on/off · ⌃⌥[ / ⌃⌥]: geser waktu lirik",
                              "⌃⌥L: compact lyrics on/off · ⌃⌥[ / ⌃⌥]: shift lyric timing")
        menu.addItem(shortcuts)
        shortcutsItem = shortcuts

        let autoPause = NSMenuItem(title: L("Pause otomatis app musik lain", "Auto-pause other music apps"),
                                   action: #selector(toggleAutoPause),
                                   keyEquivalent: "")
        autoPause.target = self
        menu.addItem(autoPause)
        autoPauseItem = autoPause

        menu.addItem(.separator())

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

        // Bahasa target terjemahan
        let target = NSMenuItem(title: L("Terjemahkan ke", "Translate to"), action: nil, keyEquivalent: "")
        let targetMenu = NSMenu()
        targetMenu.autoenablesItems = false
        for code in LyricsStore.translationTargets {
            let choice = NSMenuItem(title: languageName(code), action: #selector(setTranslationTarget(_:)), keyEquivalent: "")
            choice.target = self
            choice.representedObject = code
            targetMenu.addItem(choice)
            targetChoices.append(choice)
        }
        target.submenu = targetMenu
        menu.addItem(target)

        // Bahasa tampilan app
        let language = NSMenuItem(title: L("Bahasa", "Language"), action: nil, keyEquivalent: "")
        let languageMenu = NSMenu()
        languageMenu.autoenablesItems = false
        for lang in AppLanguage.allCases {
            let choice = NSMenuItem(title: lang.title, action: #selector(setAppLanguage(_:)), keyEquivalent: "")
            choice.target = self
            choice.representedObject = lang.rawValue
            languageMenu.addItem(choice)
            languageChoices.append(choice)
        }
        language.submenu = languageMenu
        menu.addItem(language)

        let clearCache = NSMenuItem(title: L("Hapus cache lirik…", "Clear lyrics cache…"),
                                    action: #selector(clearLyricsCache), keyEquivalent: "")
        clearCache.target = self
        menu.addItem(clearCache)

        menu.addItem(.separator())

        let login = NSMenuItem(title: L("Buka saat login", "Open at login"),
                               action: #selector(toggleLaunchAtLogin),
                               keyEquivalent: "")
        login.target = self
        menu.addItem(login)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: L("Keluar popocu", "Quit popocu"),
                                  action: #selector(quitApp),
                                  keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
        compactLyricsItem = toggle
        clickThroughItem = clickThrough
        fullWindowItem = fullWindow
        hideAfterClickItem = hideAfterClick
        loginItem = login
        refreshMenuState()
    }

    /// Selalu baca status terbaru tiap menu dibuka (bisa saja diubah dari System Settings).
    func menuWillOpen(_ menu: NSMenu) {
        refreshMenuState()
    }

    private func refreshMenuState() {
        let vm = controller?.vm
        let compactOn = vm?.showCompactLyrics ?? true
        compactLyricsItem?.state = compactOn ? .on : .off
        clickThroughItem?.state = (vm?.lyricsClickThrough ?? true) ? .on : .off
        fullWindowItem?.state = (vm?.hideLyricsWhenFullWindow ?? true) ? .on : .off
        // Dua opsi ini hanya relevan kalau baris lirik ringkas aktif.
        clickThroughItem?.isEnabled = compactOn
        fullWindowItem?.isEnabled = compactOn
        // "Sembunyikan setelah diklik" butuh tembus klik, karena kliknya harus sampai ke app di bawah.
        hideAfterClickItem?.isEnabled = compactOn && (vm?.lyricsClickThrough ?? true)
        peekItem?.state = (vm?.showTrackPeek ?? true) ? .on : .off
        karaokeItem?.state = lyrics.karaokeEnabled ? .on : .off
        karaokeItem?.isEnabled = compactOn
        accentItem?.state = (vm?.accentFromArtwork ?? false) ? .on : .off
        captureItem?.state = (vm?.hideFromScreenCapture ?? false) ? .on : .off
        shortcutsItem?.state = (vm?.shortcutsEnabled ?? true) ? .on : .off
        autoPauseItem?.state = player.autoPauseOthers ? .on : .off

        compactStyleItem?.isEnabled = compactOn
        for choice in compactStyleChoices {
            choice.state = (choice.representedObject as? String) == lyrics.compactStyle.rawValue ? .on : .off
        }

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

        for choice in targetChoices {
            choice.state = (choice.representedObject as? String) == lyrics.translationTarget ? .on : .off
        }
        for choice in languageChoices {
            choice.state = (choice.representedObject as? String) == AppLanguage.current.rawValue ? .on : .off
        }

        let seconds = vm?.hideAfterClickSeconds ?? 5
        for choice in hideAfterClickChoices {
            choice.state = (choice.representedObject as? Double) == seconds ? .on : .off
        }
        switch SMAppService.mainApp.status {
        case .enabled:
            loginItem?.state = .on
            loginItem?.title = L("Buka saat login", "Open at login")
        case .requiresApproval:
            loginItem?.state = .mixed
            loginItem?.title = L("Buka saat login (perlu disetujui)", "Open at login (needs approval)")
        default:
            loginItem?.state = .off
            loginItem?.title = L("Buka saat login", "Open at login")
        }
    }

    @objc private func toggleCompactLyrics() {
        guard let vm = controller?.vm else { return }
        vm.showCompactLyrics.toggle()
        refreshMenuState()
    }

    @objc private func toggleClickThrough() {
        guard let vm = controller?.vm else { return }
        vm.lyricsClickThrough.toggle()
        refreshMenuState()
    }

    @objc private func setHideAfterClick(_ sender: NSMenuItem) {
        guard let vm = controller?.vm, let seconds = sender.representedObject as? Double else { return }
        vm.hideAfterClickSeconds = seconds
        refreshMenuState()
    }

    @objc private func setCompactStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let style = CompactLyricStyle(rawValue: raw) else { return }
        lyrics.compactStyle = style
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

    @objc private func toggleKaraoke() {
        lyrics.karaokeEnabled.toggle()
        refreshMenuState()
    }

    @objc private func toggleAccent() {
        controller?.vm.accentFromArtwork.toggle()
        refreshMenuState()
    }

    @objc private func toggleCapture() {
        controller?.vm.hideFromScreenCapture.toggle()
        refreshMenuState()
    }

    @objc private func toggleShortcuts() {
        controller?.vm.shortcutsEnabled.toggle()
        applyShortcuts()
        refreshMenuState()
    }

    @objc private func setTranslationTarget(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        lyrics.translationTarget = code
        refreshMenuState()
    }

    @objc private func setAppLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let lang = AppLanguage(rawValue: raw),
              lang != AppLanguage.current else { return }
        UserDefaults.standard.set(lang.rawValue, forKey: AppLanguage.defaultsKey)
        relaunch()
    }

    @objc private func clearLyricsCache() {
        let alert = NSAlert()
        alert.messageText = L("Hapus cache lirik?", "Clear lyrics cache?")
        alert.informativeText = L("Semua lirik & terjemahan yang tersimpan akan diunduh ulang. Pilihan lirik manual tetap disimpan.",
                                  "All saved lyrics and translations will be downloaded again. Manually chosen lyrics are kept.")
        alert.addButton(withTitle: L("Hapus", "Clear"))
        alert.addButton(withTitle: L("Batal", "Cancel"))
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            lyrics.clearCache()
        }
    }

    /// Buka ulang app supaya bahasa baru dipakai di seluruh tampilan.
    private func relaunch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 0.7; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? process.run()
        NSApp.terminate(nil)
    }

    @objc private func toggleAutoPause() {
        player.autoPauseOthers.toggle()
        refreshMenuState()
    }

    @objc private func togglePeek() {
        guard let vm = controller?.vm else { return }
        vm.showTrackPeek.toggle()
        refreshMenuState()
    }

    @objc private func toggleFullWindow() {
        guard let vm = controller?.vm else { return }
        vm.hideLyricsWhenFullWindow.toggle()
        refreshMenuState()
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            showAlert(title: L("Gagal mengubah pengaturan login", "Couldn't change the login setting"),
                      message: "\(error.localizedDescription)\n\n" + L("Pastikan popocu sudah ada di folder Applications.", "Make sure popocu is in the Applications folder."))
        }
        // macOS kadang minta persetujuan manual di Login Items.
        if service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
        refreshMenuState()
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        NSApp.activate()
        alert.runModal()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
