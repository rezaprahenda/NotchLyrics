import Foundation

func priorityTests() {
    suite("NotchPriority.earOwner") {
        var s = NotchSituation()
        expectEqual(NotchPriority.earOwner(s), .none, "kosong")

        s.hasTrack = true; s.isPlaying = true
        expectEqual(NotchPriority.earOwner(s), .music, "musik diputar")

        s.isPlaying = false; s.pausedFor = 30
        expectEqual(NotchPriority.earOwner(s), .music, "baru di-pause tetap musik")

        s.pausedFor = 120
        expectEqual(NotchPriority.earOwner(s), .musicIdle, "pause lama turun prioritas")

        s.minutesToPrayer = 10
        expectEqual(NotchPriority.earOwner(s), .prayerSoon, "salat < 15 menit mengalahkan musik yang lama di-pause")

        s.isPlaying = true
        expectEqual(NotchPriority.earOwner(s), .music, "musik diputar mengalahkan hitung mundur salat")

        s.minutesToPrayer = 20
        s.pomodoroRunning = true
        expectEqual(NotchPriority.earOwner(s), .pomodoro, "pomodoro mengalahkan musik")

        s.minutesSincePrayer = 3
        expectEqual(NotchPriority.earOwner(s), .prayerNow, "waktu salat masuk mengalahkan semuanya")

        s.minutesSincePrayer = 12
        expectEqual(NotchPriority.earOwner(s), .pomodoro, "lewat 10 menit, kembali ke pomodoro")

        var onlyPrayer = NotchSituation()
        onlyPrayer.minutesToPrayer = 14.5
        expectEqual(NotchPriority.earOwner(onlyPrayer), .prayerSoon, "hanya salat dekat")
        onlyPrayer.minutesToPrayer = 40
        expectEqual(NotchPriority.earOwner(onlyPrayer), .none, "salat masih jauh")

        var shelf = NotchSituation()
        shelf.shelfItems = 2
        expectEqual(NotchPriority.earOwner(shelf), .shelf, "hanya ada file di rak")
        shelf.hasTrack = true
        shelf.isPlaying = true
        expectEqual(NotchPriority.earOwner(shelf), .music, "musik mengalahkan rak")
        shelf.isPlaying = false
        shelf.pausedFor = 600
        expectEqual(NotchPriority.earOwner(shelf), .musicIdle, "musik yang lama di-pause tetap di atas rak")
    }
}

func peekQueueTests() {
    suite("PeekQueue") {
        let t0 = Date(timeIntervalSince1970: 0)
        var q = PeekQueue()
        q.push(PeekEvent(kind: .trackChange, id: "lagu1", createdAt: t0))
        q.push(PeekEvent(kind: .device, id: "charger", createdAt: t0.addingTimeInterval(1)))
        q.push(PeekEvent(kind: .prayer, id: "ashar", createdAt: t0.addingTimeInterval(2)))
        expectEqual(q.next()?.kind, .prayer, "prioritas tertinggi dulu")
        expectEqual(q.next()?.kind, .device, "lalu perangkat")
        expectEqual(q.next()?.id, "lagu1", "lalu ganti lagu")
        expect(q.isEmpty, "antrian habis")

        q.push(PeekEvent(kind: .trackChange, id: "lagu1", createdAt: t0))
        q.push(PeekEvent(kind: .trackChange, id: "lagu2", createdAt: t0.addingTimeInterval(1)))
        expectEqual(q.items.count, 1, "ganti lagu yang basi dibuang")
        expectEqual(q.next()?.id, "lagu2", "yang tersisa lagu terbaru")

        q.push(PeekEvent(kind: .trackChange, id: "a", createdAt: t0))
        q.push(PeekEvent(kind: .device, id: "b", createdAt: t0))
        q.push(PeekEvent(kind: .pomodoro, id: "c", createdAt: t0))
        q.push(PeekEvent(kind: .prayer, id: "d", createdAt: t0))
        expectEqual(q.items.count, PeekQueue.capacity, "maksimal 3")
        expect(!q.items.contains { $0.kind == .trackChange }, "yang terendah dibuang saat penuh")

        expectEqual(PeekEvent.Kind.prayer.duration, 10, "peek adzan 10 detik")
        expectEqual(PeekEvent.Kind.trackChange.duration, 3, "peek ganti lagu 3 detik")
    }
}
