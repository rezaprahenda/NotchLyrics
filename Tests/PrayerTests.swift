import Foundation

func prayerTests() {
    suite("PrayerCalc vs jadwal Jakarta Oktober 2026") {
        // DKI Jakarta 6°10' LS, 106°49' BT, WIB (UTC+7). Toleransi 1 menit (beda pembulatan sumber).
        let lat = -(6 + 10.0 / 60), lon = 106 + 49.0 / 60
        let reference: [(Int, [Prayer: String])] = [
            (1, [.imsak: "04.13", .fajr: "04.23", .sunrise: "05.36", .dhuhr: "11.45", .asr: "14.51", .maghrib: "17.49", .isha: "18.59"]),
            (15, [.imsak: "04.06", .fajr: "04.16", .sunrise: "05.30", .dhuhr: "11.41", .asr: "14.46", .maghrib: "17.48", .isha: "18.58"]),
            (26, [.imsak: "04.01", .fajr: "04.11", .sunrise: "05.26", .dhuhr: "11.39", .asr: "14.51", .maghrib: "17.48", .isha: "18.59"]),
            (31, [.imsak: "03.59", .fajr: "04.09", .sunrise: "05.25", .dhuhr: "11.38", .asr: "14.54", .maghrib: "17.48", .isha: "19.00"]),
        ]
        for (day, expected) in reference {
            let got = PrayerCalc.minutes(year: 2026, month: 10, day: day, latitude: lat, longitude: lon, utcOffsetHours: 7)
            for (prayer, text) in expected {
                let parts = text.split(separator: ".").compactMap { Int($0) }
                let want = parts[0] * 60 + parts[1]
                let have = got[prayer] ?? -999
                expect(abs(have - want) <= 1,
                       "\(day) Okt \(prayer.rawValue): \(PrayerCalc.clock(have)) vs \(text)")
            }
        }
    }

    suite("PrayerCalc lain-lain") {
        let m = PrayerCalc.minutes(year: 2026, month: 10, day: 26, latitude: -6.1667, longitude: 106.8167, utcOffsetHours: 7)
        let order: [Prayer] = [.imsak, .fajr, .sunrise, .dhuhr, .asr, .maghrib, .isha]
        expect(zip(order, order.dropFirst()).allSatisfy { (m[$0] ?? 0) < (m[$1] ?? 0) }, "urutan waktu benar")
        expectEqual((m[.fajr] ?? 0) - (m[.imsak] ?? 0), 10, "Imsak = Subuh − 10 menit")
        expectEqual(PrayerCalc.clock(251), "04.11", "format jam")
        expectEqual(PrayerCalc.clock(-10), "23.50", "jam negatif dibungkus")

        // Zona waktu: Makassar (WITA, UTC+8) — Dzuhur sekitar 11.40–12.05.
        let mks = PrayerCalc.minutes(year: 2026, month: 10, day: 26, latitude: -5.1477, longitude: 119.4327, utcOffsetHours: 8)
        expect((700...725).contains(mks[.dhuhr] ?? 0), "Dzuhur Makassar masuk akal: \(PrayerCalc.clock(mks[.dhuhr] ?? 0))")

        let tz = TimeZone(identifier: "Asia/Jakarta")!
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
        let date = cal.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 9))!
        let s = PrayerCalc.schedule(for: date, latitude: -6.1667, longitude: 106.8167, timeZone: tz)
        let comps = cal.dateComponents([.hour, .minute], from: s[.dhuhr]!)
        expectEqual((comps.hour ?? 0) * 60 + (comps.minute ?? 0), m[.dhuhr] ?? 0, "schedule() = minutes() dalam Date")
    }
}
