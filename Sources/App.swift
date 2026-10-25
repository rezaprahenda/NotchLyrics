import AppKit
import SwiftUI
import ServiceManagement

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

    static func main() {
        let app = NSApplication.shared
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
    }

    // Ikon kecil di menu bar: pengaturan + tombol keluar
    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "music.note.list",
                                     accessibilityDescription: "NotchLyrics")

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false // supaya isEnabled manual di bawah dihormati

        let toggle = NSMenuItem(title: "Tampilkan lirik di mode ringkas",
                                action: #selector(toggleCompactLyrics),
                                keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)

        // Isi baris lirik ringkas: asli / latin / terjemahan / latin + terjemahan
        let styleItem = NSMenuItem(title: "Isi baris lirik", action: nil, keyEquivalent: "")
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

        let clickThrough = NSMenuItem(title: "Lirik tembus klik & memudar saat didekati",
                                      action: #selector(toggleClickThrough),
                                      keyEquivalent: "")
        clickThrough.target = self
        clickThrough.indentationLevel = 1
        menu.addItem(clickThrough)

        let hideAfterClick = NSMenuItem(title: "Sembunyikan lirik setelah diklik", action: nil, keyEquivalent: "")
        hideAfterClick.indentationLevel = 1
        let sub = NSMenu()
        sub.autoenablesItems = false
        for (title, seconds) in [("Mati", 0.0), ("3 detik", 3.0), ("5 detik", 5.0), ("10 detik", 10.0)] {
            let choice = NSMenuItem(title: title, action: #selector(setHideAfterClick(_:)), keyEquivalent: "")
            choice.target = self
            choice.representedObject = seconds
            sub.addItem(choice)
            hideAfterClickChoices.append(choice)
        }
        hideAfterClick.submenu = sub
        menu.addItem(hideAfterClick)

        let fullWindow = NSMenuItem(title: "Sembunyikan lirik saat jendela memenuhi layar",
                                    action: #selector(toggleFullWindow),
                                    keyEquivalent: "")
        fullWindow.target = self
        fullWindow.indentationLevel = 1
        menu.addItem(fullWindow)

        let peek = NSMenuItem(title: "Notifikasi ganti lagu",
                              action: #selector(togglePeek),
                              keyEquivalent: "")
        peek.target = self
        menu.addItem(peek)
        peekItem = peek

        let autoPause = NSMenuItem(title: "Pause otomatis app musik lain",
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
        for (title, minutes) in [("Mati", 0), ("15 menit", 15), ("30 menit", 30), ("45 menit", 45),
                                 ("1 jam", 60), ("Sampai lagu ini selesai", -1)] {
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

        let login = NSMenuItem(title: "Buka saat login",
                               action: #selector(toggleLaunchAtLogin),
                               keyEquivalent: "")
        login.target = self
        menu.addItem(login)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Keluar NotchLyrics",
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
        autoPauseItem?.state = player.autoPauseOthers ? .on : .off

        compactStyleItem?.isEnabled = compactOn
        for choice in compactStyleChoices {
            choice.state = (choice.representedObject as? String) == lyrics.compactStyle.rawValue ? .on : .off
        }

        // Sleep timer: tandai pilihan aktif + tampilkan sisa waktu di judul.
        let activeSleep: Int
        if player.sleepAtTrackEnd {
            activeSleep = -1
            sleepItem?.title = "Sleep timer · sampai lagu selesai"
        } else if let until = player.sleepUntil {
            let minutes = max(1, Int((until.timeIntervalSinceNow / 60).rounded(.up)))
            activeSleep = chosenSleepMinutes
            sleepItem?.title = "Sleep timer · sisa \(minutes) menit"
        } else {
            activeSleep = 0
            sleepItem?.title = "Sleep timer"
        }
        for choice in sleepChoices {
            choice.state = (choice.representedObject as? Int) == activeSleep ? .on : .off
        }

        let seconds = vm?.hideAfterClickSeconds ?? 5
        for choice in hideAfterClickChoices {
            choice.state = (choice.representedObject as? Double) == seconds ? .on : .off
        }
        switch SMAppService.mainApp.status {
        case .enabled:
            loginItem?.state = .on
            loginItem?.title = "Buka saat login"
        case .requiresApproval:
            loginItem?.state = .mixed
            loginItem?.title = "Buka saat login (perlu disetujui)"
        default:
            loginItem?.state = .off
            loginItem?.title = "Buka saat login"
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
            showAlert(title: "Gagal mengubah pengaturan login",
                      message: "\(error.localizedDescription)\n\nPastikan NotchLyrics sudah ada di folder Applications.")
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
