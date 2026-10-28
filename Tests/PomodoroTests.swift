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

    suite("PomodoroCore statistik") {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        let today = cal.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 21))!
        let week = PomodoroCore.lastDays(7, endingAt: today, calendar: cal).map { PomodoroCore.dayKey($0, calendar: cal) }
        expectEqual(week.count, 7, "7 hari")
        expectEqual(week.first, "2026-10-22", "mulai 6 hari lalu")
        expectEqual(week.last, "2026-10-28", "diakhiri hari ini")
        expectEqual(PomodoroCore.lastDays(0, endingAt: today, calendar: cal).count, 0, "n = 0 kosong")

        let stats: [String: [Int]] = ["2026-10-28": [2, 50], "2026-10-27": [1, 25], "2026-10-26": [3, 75], "2026-10-24": [1, 25]]
        expectEqual(PomodoroCore.streak(stats, today: today, calendar: cal), 3, "3 hari beruntun (24 tidak tersambung)")
        var noToday = stats; noToday["2026-10-28"] = nil
        expectEqual(PomodoroCore.streak(noToday, today: today, calendar: cal), 2, "hari ini belum fokus: rentetan tetap dari kemarin")
        var broken = noToday; broken["2026-10-27"] = nil
        expectEqual(PomodoroCore.streak(broken, today: today, calendar: cal), 0, "kemarin kosong: rentetan putus")
        expectEqual(PomodoroCore.streak(["2026-10-28": [0, 0]], today: today, calendar: cal), 0, "0 sesi tidak dihitung")
    }
}
