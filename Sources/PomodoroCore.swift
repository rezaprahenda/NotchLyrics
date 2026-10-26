import Foundation

// Logika pomodoro murni (tanpa timer / UI), dites di Tests/.

enum PomodoroPhase: String, Codable {
    case idle, focus, shortBreak, longBreak

    var isBreak: Bool { self == .shortBreak || self == .longBreak }
}

struct PomodoroSettings: Codable, Equatable {
    var focusMinutes = 25
    var shortBreakMinutes = 5
    var longBreakMinutes = 15
    /// Istirahat panjang setelah sekian sesi fokus.
    var sessionsBeforeLongBreak = 4

    static let presets: [(focus: Int, rest: Int)] = [(25, 5), (50, 10)]
}

enum PomodoroCore {
    /// Fase berikutnya setelah `phase` selesai. `completedFocus` = jumlah sesi fokus yang sudah
    /// selesai dalam siklus ini, termasuk yang barusan.
    static func next(after phase: PomodoroPhase, completedFocus: Int, settings: PomodoroSettings) -> PomodoroPhase {
        switch phase {
        case .focus:
            let every = max(settings.sessionsBeforeLongBreak, 1)
            return completedFocus > 0 && completedFocus % every == 0 ? .longBreak : .shortBreak
        case .shortBreak, .longBreak, .idle:
            return .focus
        }
    }

    static func duration(of phase: PomodoroPhase, settings: PomodoroSettings) -> TimeInterval {
        switch phase {
        case .focus: return TimeInterval(max(settings.focusMinutes, 1) * 60)
        case .shortBreak: return TimeInterval(max(settings.shortBreakMinutes, 1) * 60)
        case .longBreak: return TimeInterval(max(settings.longBreakMinutes, 1) * 60)
        case .idle: return 0
        }
    }

    /// "18:42" — sisa waktu dibulatkan ke atas, supaya tidak menampilkan 00:00 sebelum selesai.
    static func clock(_ seconds: TimeInterval) -> String {
        let s = max(Int(seconds.rounded(.up)), 0)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// Kunci statistik harian, mis. "2026-10-26" (zona waktu lokal).
    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
