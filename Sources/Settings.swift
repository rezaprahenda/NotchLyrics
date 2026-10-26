import SwiftUI
import AppKit
import ServiceManagement

/// Jendela Pengaturan (menggantikan menu panjang di menu bar).
final class SettingsWindowController {
    private var window: NSWindow?

    func show(vm: NotchViewModel, player: PlayerMonitor, lyrics: LyricsStore, pomodoro: PomodoroModule) {
        if window == nil {
            let view = SettingsView(vm: vm, player: player, lyrics: lyrics, pomodoro: pomodoro)
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

    var body: some View {
        TabView {
            GeneralSettings(vm: vm, player: player, lyrics: lyrics)
                .tabItem { Label(L("Umum", "General"), systemImage: "gearshape") }
            MusicSettings(vm: vm, lyrics: lyrics)
                .tabItem { Label(L("Musik & lirik", "Music & lyrics"), systemImage: "music.note") }
            FocusSettings(pomodoro: pomodoro)
                .tabItem { Label(L("Fokus", "Focus"), systemImage: "timer") }
        }
        .frame(width: 520, height: 470)
    }
}

// MARK: - Umum

struct GeneralSettings: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var player: PlayerMonitor
    @ObservedObject var lyrics: LyricsStore
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

            Section(L("Notch", "Notch")) {
                Toggle(L("Notifikasi ganti lagu", "Track change banner"), isOn: $vm.showTrackPeek)
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
