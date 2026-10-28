import Foundation
import Combine

/// Apa yang dilakukan pada musik saat fase pomodoro berganti.
enum PomodoroMusicPolicy: String, CaseIterable {
    /// Musik tidak disentuh (default).
    case untouched
    /// Musik di-pause selama istirahat, lanjut lagi saat fokus.
    case pauseOnBreak
    /// Musik di-pause selama fokus, lanjut lagi saat istirahat.
    case pauseOnFocus

    var title: String {
        switch self {
        case .untouched: return L("Biarkan musik", "Leave music alone")
        case .pauseOnBreak: return L("Pause saat istirahat", "Pause during breaks")
        case .pauseOnFocus: return L("Pause saat fokus", "Pause while focusing")
        }
    }
}

enum PomodoroEvent {
    case phaseStarted(PomodoroPhase)
    /// Fase selesai; `next` menunggu konfirmasi pengguna (tidak dimulai diam-diam).
    case phaseEnded(PomodoroPhase, next: PomodoroPhase)
    case reminder(title: String, subtitle: String)
}

/// Modul pomodoro: satu `Timer` ke titik selesai berikutnya, bukan detak tiap detik.
final class PomodoroModule: ObservableObject {
    @Published private(set) var phase: PomodoroPhase = .idle
    @Published private(set) var endsAt: Date?
    /// Non-nil = sedang dijeda, berisi sisa waktu.
    @Published private(set) var pausedRemaining: TimeInterval?
    /// Fase berikutnya yang menunggu tombol "Mulai".
    @Published private(set) var waitingFor: PomodoroPhase?
    /// Sesi fokus yang selesai dalam siklus ini (reset setelah istirahat panjang).
    @Published private(set) var cycleFocusDone = 0
    @Published private(set) var todaySessions = 0
    @Published private(set) var todayFocusMinutes = 0
    /// Menit fokus 7 hari terakhir (terlama → hari ini) dan hari beruntun, untuk grafik di halaman Fokus.
    @Published private(set) var weekMinutes: [Int] = Array(repeating: 0, count: 7)
    @Published private(set) var streakDays = 0

    @Published var enabled: Bool = Defaults.bool("pomodoro.enabled", true) {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "pomodoro.enabled")
            if !enabled { stop() }
        }
    }
    @Published var settings: PomodoroSettings = PomodoroModule.loadSettings() {
        didSet {
            if let data = try? JSONEncoder().encode(settings) {
                UserDefaults.standard.set(data, forKey: "pomodoro.settings")
            }
        }
    }
    @Published var musicPolicy: PomodoroMusicPolicy =
        PomodoroMusicPolicy(rawValue: UserDefaults.standard.string(forKey: "pomodoro.music") ?? "") ?? .untouched {
        didSet { UserDefaults.standard.set(musicPolicy.rawValue, forKey: "pomodoro.music") }
    }
    /// Pengingat selama fokus (menit; 0 = mati).
    @Published var waterReminderMinutes: Int = Defaults.int("pomodoro.water", 0) {
        didSet { UserDefaults.standard.set(waterReminderMinutes, forKey: "pomodoro.water"); scheduleReminders() }
    }
    @Published var standReminderMinutes: Int = Defaults.int("pomodoro.stand", 0) {
        didSet { UserDefaults.standard.set(standReminderMinutes, forKey: "pomodoro.stand"); scheduleReminders() }
    }

    /// Dipasang oleh controller: peek, musik, dll.
    var onEvent: ((PomodoroEvent) -> Void)?

    private var timer: Timer?
    private var reminderTimers: [Timer] = []
    private static let statsKey = "pomodoro.stats"

    private var dayObserver: NSObjectProtocol?

    init() {
        loadToday()
        // Lewat tengah malam: angka "hari ini" dan grafik mingguan ikut bergeser.
        dayObserver = NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil,
                                                             queue: .main) { [weak self] _ in self?.loadToday() }
    }

    // MARK: - Status

    /// Ada sesi berjalan, dijeda, atau menunggu konfirmasi.
    var isActive: Bool { phase != .idle || waitingFor != nil }
    var isPaused: Bool { pausedRemaining != nil }
    var isFocusRunning: Bool { phase == .focus && !isPaused }

    var totalDuration: TimeInterval { PomodoroCore.duration(of: phase, settings: settings) }

    func remaining(at now: Date = Date()) -> TimeInterval {
        if let pausedRemaining { return pausedRemaining }
        guard let endsAt else { return 0 }
        return max(endsAt.timeIntervalSince(now), 0)
    }

    func progress(at now: Date = Date()) -> Double {
        let total = totalDuration
        guard total > 0 else { return 0 }
        return min(max(1 - remaining(at: now) / total, 0), 1)
    }

    // MARK: - Kontrol

    func start(_ newPhase: PomodoroPhase = .focus) {
        guard enabled, newPhase != .idle else { return }
        timer?.invalidate()
        waitingFor = nil
        pausedRemaining = nil
        phase = newPhase
        let end = Date().addingTimeInterval(PomodoroCore.duration(of: newPhase, settings: settings))
        endsAt = end
        scheduleEnd(at: end)
        scheduleReminders()
        onEvent?(.phaseStarted(newPhase))
    }

    /// Mulai fokus dengan preset (mis. 25/5 atau 50/10).
    func start(focus: Int, rest: Int) {
        settings.focusMinutes = focus
        settings.shortBreakMinutes = rest
        cycleFocusDone = 0
        start(.focus)
    }

    func pause() {
        guard phase != .idle, pausedRemaining == nil else { return }
        pausedRemaining = remaining()
        timer?.invalidate()
        timer = nil
        endsAt = nil
        scheduleReminders()
    }

    func resume() {
        guard let left = pausedRemaining else { return }
        pausedRemaining = nil
        let end = Date().addingTimeInterval(left)
        endsAt = end
        scheduleEnd(at: end)
        scheduleReminders()
    }

    func togglePause() {
        if isPaused { resume() } else if phase != .idle { pause() } else if let next = waitingFor { start(next) } else { start(.focus) }
    }

    /// Mulai fase yang sedang menunggu konfirmasi.
    func acceptNext() {
        guard let next = waitingFor else { return }
        start(next)
    }

    /// Lewati fase yang menunggu (mis. istirahat) dan langsung ke fase sesudahnya.
    func skipNext() {
        guard let next = waitingFor else { return }
        start(next.isBreak ? .focus : PomodoroCore.next(after: .focus, completedFocus: cycleFocusDone, settings: settings))
    }

    /// Akhiri fase sekarang tanpa menghitungnya sebagai sesi selesai.
    func skipCurrent() {
        guard phase != .idle else { skipNext(); return }
        let current = phase
        let next = current == .focus
            ? PomodoroCore.next(after: .focus, completedFocus: cycleFocusDone + 1, settings: settings)
            : .focus
        start(next)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        phase = .idle
        endsAt = nil
        pausedRemaining = nil
        waitingFor = nil
        cycleFocusDone = 0
        scheduleReminders()
    }

    // MARK: - Internal

    private func scheduleEnd(at date: Date) {
        timer?.invalidate()
        let t = Timer(fire: date, interval: 0, repeats: false) { [weak self] _ in self?.finishPhase() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func finishPhase() {
        let finished = phase
        guard finished != .idle else { return }
        timer = nil
        if finished == .focus {
            cycleFocusDone += 1
            record(minutes: settings.focusMinutes)
        }
        let next = PomodoroCore.next(after: finished, completedFocus: cycleFocusDone, settings: settings)
        if finished == .longBreak { cycleFocusDone = 0 }
        phase = .idle
        endsAt = nil
        waitingFor = next
        scheduleReminders()
        onEvent?(.phaseEnded(finished, next: next))
    }

    /// Pengingat minum / berdiri hanya selama fokus berjalan.
    private func scheduleReminders() {
        reminderTimers.forEach { $0.invalidate() }
        reminderTimers = []
        guard isFocusRunning else { return }
        let reminders: [(Int, String, String)] = [
            (waterReminderMinutes, L("Waktunya minum air", "Time for some water"), L("Tetap terhidrasi", "Stay hydrated")),
            (standReminderMinutes, L("Waktunya berdiri", "Time to stand up"), L("Regangkan badan sebentar", "Stretch for a moment")),
        ]
        for (minutes, title, subtitle) in reminders where minutes > 0 {
            let t = Timer(timeInterval: TimeInterval(minutes * 60), repeats: true) { [weak self] _ in
                self?.onEvent?(.reminder(title: title, subtitle: subtitle))
            }
            RunLoop.main.add(t, forMode: .common)
            reminderTimers.append(t)
        }
    }

    // MARK: - Statistik harian

    private func loadToday() {
        let stats = UserDefaults.standard.dictionary(forKey: Self.statsKey) as? [String: [Int]] ?? [:]
        let today = stats[PomodoroCore.dayKey(Date())] ?? [0, 0]
        todaySessions = today.first ?? 0
        todayFocusMinutes = today.count > 1 ? today[1] : 0
        refreshWeek(stats)
    }

    private func refreshWeek(_ stats: [String: [Int]]) {
        let now = Date()
        weekMinutes = PomodoroCore.lastDays(7, endingAt: now).map { day in
            let v = stats[PomodoroCore.dayKey(day)] ?? []
            return v.count > 1 ? v[1] : 0
        }
        streakDays = PomodoroCore.streak(stats, today: now)
    }

    private func record(minutes: Int) {
        var stats = UserDefaults.standard.dictionary(forKey: Self.statsKey) as? [String: [Int]] ?? [:]
        let key = PomodoroCore.dayKey(Date())
        var today = stats[key] ?? [0, 0]
        if today.count < 2 { today = [today.first ?? 0, 0] }
        today[0] += 1
        today[1] += minutes
        stats[key] = today
        // Simpan 60 hari terakhir saja.
        if stats.count > 60 {
            for old in stats.keys.sorted().prefix(stats.count - 60) { stats[old] = nil }
        }
        UserDefaults.standard.set(stats, forKey: Self.statsKey)
        todaySessions = today[0]
        todayFocusMinutes = today[1]
        refreshWeek(stats)
    }

    private static func loadSettings() -> PomodoroSettings {
        guard let data = UserDefaults.standard.data(forKey: "pomodoro.settings"),
              let s = try? JSONDecoder().decode(PomodoroSettings.self, from: data)
        else { return PomodoroSettings() }
        return s
    }
}

/// Pembaca UserDefaults dengan nilai bawaan.
enum Defaults {
    static func bool(_ key: String, _ fallback: Bool) -> Bool {
        (UserDefaults.standard.object(forKey: key) as? Bool) ?? fallback
    }
    static func int(_ key: String, _ fallback: Int) -> Int {
        (UserDefaults.standard.object(forKey: key) as? Int) ?? fallback
    }
}
