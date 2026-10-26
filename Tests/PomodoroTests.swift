import Foundation

func pomodoroTests() {
    suite("PomodoroCore") {
        let s = PomodoroSettings()
        expectEqual(PomodoroCore.next(after: .focus, completedFocus: 1, settings: s), .shortBreak, "fokus 1 → istirahat pendek")
        expectEqual(PomodoroCore.next(after: .focus, completedFocus: 3, settings: s), .shortBreak, "fokus 3 → istirahat pendek")
        expectEqual(PomodoroCore.next(after: .focus, completedFocus: 4, settings: s), .longBreak, "fokus 4 → istirahat panjang")
        expectEqual(PomodoroCore.next(after: .focus, completedFocus: 8, settings: s), .longBreak, "fokus 8 → istirahat panjang")
        expectEqual(PomodoroCore.next(after: .shortBreak, completedFocus: 2, settings: s), .focus, "istirahat → fokus")
        expectEqual(PomodoroCore.next(after: .longBreak, completedFocus: 0, settings: s), .focus, "istirahat panjang → fokus")

        var custom = s
        custom.sessionsBeforeLongBreak = 0
        expectEqual(PomodoroCore.next(after: .focus, completedFocus: 1, settings: custom), .longBreak,
                    "nilai 0 dianggap 1 (tidak crash bagi nol)")

        expectEqual(PomodoroCore.duration(of: .focus, settings: s), 1500, "25 menit")
        expectEqual(PomodoroCore.duration(of: .shortBreak, settings: s), 300, "5 menit")
        expectEqual(PomodoroCore.duration(of: .longBreak, settings: s), 900, "15 menit")
        expectEqual(PomodoroCore.duration(of: .idle, settings: s), 0, "idle = 0")

        expectEqual(PomodoroCore.clock(1122), "18:42", "format jam")
        expectEqual(PomodoroCore.clock(59.2), "1:00", "dibulatkan ke atas")
        expectEqual(PomodoroCore.clock(-3), "0:00", "tidak negatif")

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        // 2026-10-26 17:30 UTC = 2026-10-27 00:30 WIB
        expectEqual(PomodoroCore.dayKey(Date(timeIntervalSince1970: 1_793_035_800), calendar: cal), "2026-10-27",
                    "tanggal mengikuti zona waktu lokal")
    }
}
