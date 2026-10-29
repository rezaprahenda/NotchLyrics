import SwiftUI
import AppKit
import ServiceManagement
import UniformTypeIdentifiers

/// Jendela Pengaturan (menggantikan menu panjang di menu bar).
final class SettingsWindowController {
    private var window: NSWindow?

    func show(vm: NotchViewModel, player: PlayerMonitor, lyrics: LyricsStore, pomodoro: PomodoroModule,
              prayer: PrayerModule, shelf: ShelfModule, device: DeviceModule,
              mirror: MirrorModule, clipboard: ClipboardModule, lastfm: LastFMModule) {
        if window == nil {
            let view = SettingsView(vm: vm, player: player, lyrics: lyrics, pomodoro: pomodoro, prayer: prayer,
                                    shelf: shelf, device: device, mirror: mirror,
                                    clipboard: clipboard, lastfm: lastfm)
            let host = NSHostingController(rootView: view)
            let w = NSWindow(contentViewController: host)
            w.title = L("Pengaturan popocu", "popocu Settings")
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

enum AppRelaunch {
    /// Buka ulang app (dipakai saat bahasa diganti).
    static func now() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 0.7; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? process.run()
        NSApp.terminate(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var player: PlayerMonitor
    @ObservedObject var lyrics: LyricsStore
    @ObservedObject var pomodoro: PomodoroModule
    @ObservedObject var prayer: PrayerModule
    @ObservedObject var shelf: ShelfModule
    @ObservedObject var device: DeviceModule
    @ObservedObject var mirror: MirrorModule
    @ObservedObject var clipboard: ClipboardModule
    @ObservedObject var lastfm: LastFMModule

    var body: some View {
        VStack(spacing: 0) {
            tabs
            Divider()
            AboutFooter()
        }
        .frame(width: 540, height: 556)
    }

    private var tabs: some View {
        TabView {
            GeneralSettings(vm: vm, player: player, lyrics: lyrics, pomodoro: pomodoro, prayer: prayer,
                            shelf: shelf, device: device, mirror: mirror, clipboard: clipboard)
                .tabItem { Label(L("Umum", "General"), systemImage: "gearshape") }
            MusicSettings(vm: vm, lyrics: lyrics, lastfm: lastfm)
                .tabItem { Label(L("Musik & lirik", "Music & lyrics"), systemImage: "music.note") }
            FocusSettings(pomodoro: pomodoro)
                .tabItem { Label(L("Fokus", "Focus"), systemImage: "timer") }
            PrayerSettings(prayer: prayer)
                .tabItem { Label(L("Salat", "Prayer"), systemImage: "moon.stars") }
        }
    }
}

/// Baris "tentang" di bawah Pengaturan, sama gayanya dengan keluarga -cu lain.
struct AboutFooter: View {
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    private let profile = URL(string: "https://instagram.com/rezaprahenda")!

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 14, height: 14)
            Text("popocu").fontWeight(.semibold)
            Text("v\(version)").foregroundStyle(.secondary)
            Text("pop-a-cu!").italic().foregroundStyle(.secondary)
            Spacer()
            Text("made by").foregroundStyle(.secondary)
            Link("@rezaprahenda", destination: profile)
                .help("instagram.com/rezaprahenda")
        }
        .font(.caption)
        .padding(.horizontal, 16)
        .frame(height: 36)
    }
}

// MARK: - Umum

struct GeneralSettings: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var player: PlayerMonitor
    @ObservedObject var lyrics: LyricsStore
    @ObservedObject var pomodoro: PomodoroModule
    @ObservedObject var prayer: PrayerModule
    @ObservedObject var shelf: ShelfModule
    @ObservedObject var device: DeviceModule
    @ObservedObject var mirror: MirrorModule
    @ObservedObject var clipboard: ClipboardModule
    @ObservedObject private var weather = WeatherModule.shared
    @State private var language = AppLanguage.current
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var confirmClear = false

    var body: some View {
        Form {
            Section {
                Picker(L("Bahasa", "Language"), selection: $language) {
                    ForEach(AppLanguage.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                if language != AppLanguage.current {
                    HStack {
                        Text(L("popocu perlu dibuka ulang.", "popocu needs to restart."))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(L("Buka ulang", "Restart")) {
                            UserDefaults.standard.set(language.rawValue, forKey: AppLanguage.defaultsKey)
                            AppRelaunch.now()
                        }
                    }
                }
                Toggle(L("Buka saat login", "Open at login"),
                       isOn: Binding(get: { loginStatus == .enabled }, set: { setLogin($0) }))
                if loginStatus == .requiresApproval {
                    Text(L("Perlu disetujui di System Settings › General › Login Items.",
                           "Needs approval in System Settings › General › Login Items."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(L("Modul (tab di panel penuh)", "Modules (tabs in the full panel)")) {
                Toggle(L("Pomodoro", "Pomodoro"), isOn: $pomodoro.enabled)
                Toggle(L("Jadwal salat & adzan (minta izin lokasi, atau pilih kota)",
                         "Prayer times & adhan (asks for location, or choose a city)"), isOn: $prayer.enabled)
                Toggle(L("Rak file (seret file ke notch)", "File shelf (drag files onto the notch)"), isOn: $shelf.enabled)
                Toggle(L("Kamera cermin (kamera hanya menyala saat halamannya dibuka)",
                         "Camera mirror (camera runs only while its page is open)"), isOn: $mirror.enabled)
                Toggle(L("Riwayat clipboard (10 teks, tidak disimpan ke disk)",
                         "Clipboard history (10 texts, never saved to disk)"), isOn: $clipboard.enabled)
                Toggle(L("Cuaca di samping jam (lokasi sama dengan Salat, data Open-Meteo)",
                         "Weather next to the clock (same location as Prayer, data from Open-Meteo)"),
                       isOn: $weather.enabled)
            }

            Section(L("Notch", "Notch")) {
                Picker(L("Gaya", "Style"), selection: $vm.panelStyle) {
                    ForEach(PanelStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(L("Hidup: gradasi & cahaya halus · Kaca: bagian bawah tembus pandang buram · Polos: hitam rata",
                       "Vivid: gradient & soft light · Glass: frosted lower part · Plain: flat black"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker(L("Tampilkan di", "Show on"), selection: $vm.displayPreference) {
                    ForEach(DisplayPreference.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle(L("Notifikasi ganti lagu", "Track change banner"), isOn: $vm.showTrackPeek)
                Toggle(L("Diam saat mode Focus aktif (kecuali salat & pomodoro)",
                         "Stay quiet during Focus (except prayer & pomodoro)"), isOn: $vm.respectFocus)
                Toggle(L("Sembunyikan saat share screen & rekam layar", "Hide during screen sharing & recording"),
                       isOn: $vm.hideFromScreenCapture)
                Toggle(L("Shortcut keyboard", "Keyboard shortcuts"), isOn: $vm.shortcutsEnabled)
                Text(L("⌃⌥L lirik on/off · ⌃⌥[ / ⌃⌥] geser waktu lirik · ⌃⌥P pomodoro mulai/jeda",
                       "⌃⌥L lyrics on/off · ⌃⌥[ / ⌃⌥] shift lyric timing · ⌃⌥P start/pause pomodoro"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L("Musik", "Music")) {
                Toggle(L("Pause otomatis app musik lain", "Auto-pause other music apps"), isOn: $player.autoPauseOthers)
            }

            Section(L("Perangkat", "Devices")) {
                Toggle(L("Notifikasi charger & baterai lemah", "Charger & low battery banners"), isOn: $device.batteryAlerts)
                Toggle(L("Notifikasi headphone Bluetooth tersambung", "Bluetooth headphones connected banner"),
                       isOn: $device.audioAlerts)
            }

            Section {
                Button(L("Hapus cache lirik…", "Clear lyrics cache…")) { confirmClear = true }
            }
        }
        .formStyle(.grouped)
        .onAppear { loginStatus = SMAppService.mainApp.status }
        .confirmationDialog(L("Hapus cache lirik?", "Clear lyrics cache?"), isPresented: $confirmClear) {
            Button(L("Hapus", "Clear"), role: .destructive) { lyrics.clearCache() }
        } message: {
            Text(L("Semua lirik & terjemahan yang tersimpan akan diunduh ulang. Pilihan lirik manual tetap disimpan.",
                   "All saved lyrics and translations will be downloaded again. Manually chosen lyrics are kept."))
        }
    }

    private func setLogin(_ on: Bool) {
        let service = SMAppService.mainApp
        do {
            if on { try service.register() } else { try service.unregister() }
        } catch {
            NSLog("popocu: gagal mengubah login item: %@", error.localizedDescription)
        }
        loginStatus = service.status
        if loginStatus == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    }
}

// MARK: - Musik & lirik

struct MusicSettings: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var lyrics: LyricsStore
    @ObservedObject var lastfm: LastFMModule

    var body: some View {
        Form {
            Section(L("Baris lirik di bawah notch", "Lyric line under the notch")) {
                Toggle(L("Tampilkan lirik di mode ringkas", "Show lyrics in compact mode"), isOn: $vm.showCompactLyrics)
                Picker(L("Isi baris lirik", "Lyric line content"), selection: $lyrics.compactStyle) {
                    ForEach(CompactLyricStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .disabled(!vm.showCompactLyrics)
                Toggle(L("Karaoke (baris terisi mengikuti lagu)", "Karaoke (lines fill as they are sung)"),
                       isOn: $lyrics.karaokeEnabled)
                Toggle(L("Tembus klik & memudar saat didekati", "Click-through, fades on approach"),
                       isOn: $vm.lyricsClickThrough)
                Picker(L("Sembunyikan setelah diklik", "Hide after clicking"), selection: $vm.hideAfterClickSeconds) {
                    Text(L("Mati", "Off")).tag(0.0)
                    Text(L("3 detik", "3 seconds")).tag(3.0)
                    Text(L("5 detik", "5 seconds")).tag(5.0)
                    Text(L("10 detik", "10 seconds")).tag(10.0)
                }
                .disabled(!vm.lyricsClickThrough)
                Toggle(L("Sembunyikan saat jendela memenuhi layar", "Hide when a window fills the screen"),
                       isOn: $vm.hideLyricsWhenFullWindow)
            }

            Section(L("Warna", "Color")) {
                Toggle(L("Warna mengikuti cover album", "Match colors to album art"), isOn: $vm.accentFromArtwork)
            }

            Section(L("Terjemahan", "Translation")) {
                Picker(L("Terjemahkan ke", "Translate to"), selection: $lyrics.translationTarget) {
                    ForEach(LyricsStore.translationTargets, id: \.self) { Text(languageName($0)).tag($0) }
                }
            }

            Section("Last.fm") {
                if lastfm.isConnected {
                    HStack {
                        Text(L("Tersambung sebagai \(lastfm.username ?? "")", "Connected as \(lastfm.username ?? "")"))
                        Spacer()
                        Button(L("Putuskan", "Disconnect")) { lastfm.disconnect() }
                    }
                    Toggle(L("Hanya Apple Music (Spotify bisa scrobble sendiri)", "Apple Music only (Spotify scrobbles on its own)"),
                           isOn: $lastfm.onlyAppleMusic)
                } else {
                    TextField("API key", text: $lastfm.apiKey)
                    SecureField("Shared secret", text: $lastfm.apiSecret)
                    HStack {
                        Link(L("Buat API key gratis…", "Get a free API key…"),
                             destination: URL(string: "https://www.last.fm/api/account/create")!)
                        Spacer()
                        if lastfm.awaitingApproval {
                            Button(L("Selesai", "Done")) { lastfm.finishAuth() }
                        } else {
                            Button(L("Hubungkan", "Connect")) { lastfm.beginAuth() }
                        }
                    }
                }
                if !lastfm.status.isEmpty {
                    Text(lastfm.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Fokus

struct FocusSettings: View {
    @ObservedObject var pomodoro: PomodoroModule

    var body: some View {
        Form {
            Section {
                Toggle(L("Aktifkan pomodoro", "Enable pomodoro"), isOn: $pomodoro.enabled)
            }

            Section(L("Durasi", "Durations")) {
                Stepper(value: $pomodoro.settings.focusMinutes, in: 5...120, step: 5) {
                    Text(L("Fokus: \(pomodoro.settings.focusMinutes) menit", "Focus: \(pomodoro.settings.focusMinutes) min"))
                }
                Stepper(value: $pomodoro.settings.shortBreakMinutes, in: 1...30) {
                    Text(L("Istirahat: \(pomodoro.settings.shortBreakMinutes) menit", "Break: \(pomodoro.settings.shortBreakMinutes) min"))
                }
                Stepper(value: $pomodoro.settings.longBreakMinutes, in: 5...60, step: 5) {
                    Text(L("Istirahat panjang: \(pomodoro.settings.longBreakMinutes) menit",
                           "Long break: \(pomodoro.settings.longBreakMinutes) min"))
                }
                Stepper(value: $pomodoro.settings.sessionsBeforeLongBreak, in: 2...8) {
                    Text(L("Istirahat panjang setiap \(pomodoro.settings.sessionsBeforeLongBreak) sesi",
                           "Long break every \(pomodoro.settings.sessionsBeforeLongBreak) sessions"))
                }
            }
            .disabled(!pomodoro.enabled)

            Section(L("Musik", "Music")) {
                Picker(L("Saat fase berganti", "When the phase changes"), selection: $pomodoro.musicPolicy) {
                    ForEach(PomodoroMusicPolicy.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
            .disabled(!pomodoro.enabled)

            Section(L("Pengingat selama fokus", "Reminders while focusing")) {
                Picker(L("Minum air", "Drink water"), selection: $pomodoro.waterReminderMinutes) {
                    Text(L("Mati", "Off")).tag(0)
                    ForEach([20, 30, 45, 60], id: \.self) { Text(L("Tiap \($0) menit", "Every \($0) min")).tag($0) }
                }
                Picker(L("Berdiri", "Stand up"), selection: $pomodoro.standReminderMinutes) {
                    Text(L("Mati", "Off")).tag(0)
                    ForEach([30, 45, 60, 90], id: \.self) { Text(L("Tiap \($0) menit", "Every \($0) min")).tag($0) }
                }
            }
            .disabled(!pomodoro.enabled)
        }
        .formStyle(.grouped)
    }
}

// MARK: - Salat

struct PrayerSettings: View {
    @ObservedObject var prayer: PrayerModule

    var body: some View {
        Form {
            Section {
                Toggle(L("Aktifkan jadwal salat & adzan", "Enable prayer times & adhan"), isOn: $prayer.enabled)
                Text(L("Dihitung di Mac ini dengan metode Kemenag RI (Subuh 20°, Isya 18°, ihtiyat 2 menit).",
                       "Calculated on this Mac using the Indonesian Ministry of Religious Affairs method (Fajr 20°, Isha 18°)."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L("Lokasi", "Location")) {
                Picker(L("Sumber lokasi", "Location source"), selection: $prayer.locationMode) {
                    Text(L("Otomatis (lokasi Mac)", "Automatic (Mac location)")).tag(PrayerLocationMode.automatic)
                    Text(L("Pilih kota", "Choose a city")).tag(PrayerLocationMode.manual)
                }
                if prayer.locationMode == .manual {
                    Picker(L("Kota", "City"), selection: $prayer.manualCityID) {
                        ForEach(PrayerCity.all) { Text($0.name).tag($0.id) }
                    }
                } else {
                    HStack {
                        Text(prayer.placeName.isEmpty ? L("Belum ada lokasi", "No location yet") : prayer.placeName)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(L("Perbarui", "Refresh")) { prayer.refreshLocation() }
                    }
                    if prayer.locationDenied {
                        HStack {
                            Text(L("Izin lokasi ditolak.", "Location access is off."))
                                .foregroundStyle(.orange)
                            Spacer()
                            Button(L("Buka Pengaturan Sistem", "Open System Settings")) {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }
                    }
                }
            }
            .disabled(!prayer.enabled)

            Section(L("Adzan", "Adhan")) {
                Picker(L("Suara", "Sound"), selection: $prayer.adhanSound) {
                    ForEach(AdhanSound.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                if prayer.adhanSound == .file {
                    HStack {
                        Text(prayer.adhanFilePath.isEmpty
                             ? L("Belum ada file", "No file chosen")
                             : (prayer.adhanFilePath as NSString).lastPathComponent)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Button(L("Pilih…", "Choose…")) { chooseFile() }
                    }
                }
                HStack {
                    Text(L("Tidak berbunyi saat mikrofon sedang dipakai (rapat/telepon).",
                           "Stays silent while the microphone is in use (calls/meetings)."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(L("Coba", "Test")) { prayer.playAdhan() }
                        .disabled(prayer.adhanSound == .off)
                }
                Toggle(L("Pengingat 15 & 5 menit sebelumnya", "Reminders 15 & 5 minutes before"), isOn: $prayer.preAlerts)
                Toggle(L("Jeda pomodoro saat adzan", "Pause pomodoro at adhan"), isOn: $prayer.pausePomodoroAtAdhan)
                Toggle(L("Pause musik saat adzan", "Pause music at adhan"), isOn: $prayer.pauseMusicAtAdhan)
            }
            .disabled(!prayer.enabled)

            Section(L("Ramadan", "Ramadan")) {
                Picker(L("Mode Ramadan", "Ramadan mode"), selection: $prayer.ramadanMode) {
                    ForEach(RamadanMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Text(L("Menampilkan Imsak dan hitung mundur berbuka satu jam sebelum Maghrib.",
                       "Shows Imsak and an iftar countdown during the hour before Maghrib."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!prayer.enabled)
        }
        .formStyle(.grouped)
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            prayer.adhanFilePath = url.path
        }
    }
}
