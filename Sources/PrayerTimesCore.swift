import Foundation

// Perhitungan jadwal salat murni (tanpa lokasi / UI), dites di Tests/.
// Algoritma posisi matahari mengikuti praytimes.org; parameter mengikuti Kemenag RI:
// Subuh 20°, Isya 18°, Ashar mazhab Syafi'i (bayangan 1×), ihtiyat 2 menit (Terbit −2),
// dibulatkan ke atas ke menit; Imsak = Subuh − 10 menit.

enum Prayer: String, CaseIterable, Codable {
    case imsak, fajr, sunrise, dhuhr, asr, maghrib, isha

    /// Lima waktu salat wajib (yang memicu adzan).
    var isObligatory: Bool {
        switch self {
        case .fajr, .dhuhr, .asr, .maghrib, .isha: return true
        case .imsak, .sunrise: return false
        }
    }

    var title: String {
        switch self {
        case .imsak: return "Imsak"
        case .fajr: return L("Subuh", "Fajr")
        case .sunrise: return L("Terbit", "Sunrise")
        case .dhuhr: return L("Dzuhur", "Dhuhr")
        case .asr: return L("Ashar", "Asr")
        case .maghrib: return "Maghrib"
        case .isha: return L("Isya", "Isha")
        }
    }
}

struct PrayerParameters: Equatable {
    var fajrAngle = 20.0
    var ishaAngle = 18.0
    /// 1 = Syafi'i / jumhur, 2 = Hanafi.
    var asrShadowFactor = 1.0
    var ihtiyatMinutes = 2
    var imsakMinutesBeforeFajr = 10

    static let kemenag = PrayerParameters()
}

enum PrayerCalc {
    /// Menit sejak tengah malam waktu lokal untuk setiap waktu salat.
    static func minutes(year: Int, month: Int, day: Int,
                        latitude: Double, longitude: Double, utcOffsetHours: Double,
                        parameters p: PrayerParameters = .kemenag) -> [Prayer: Int] {
        let jd = julian(year, month, day) - longitude / (15 * 24)

        func midDay(_ t: Double) -> Double { fixHour(12 - sunPosition(jd + t).equation) }

        func angleTime(_ angle: Double, _ t: Double, counterClockwise: Bool) -> Double {
            let decl = sunPosition(jd + t).declination
            let noon = midDay(t)
            let cosT = (-sin(rad(angle)) - sin(rad(decl)) * sin(rad(latitude))) / (cos(rad(decl)) * cos(rad(latitude)))
            let T = deg(acos(min(max(cosT, -1), 1))) / 15
            return counterClockwise ? noon - T : noon + T
        }

        func asrTime(_ t: Double) -> Double {
            let decl = sunPosition(jd + t).declination
            let angle = -deg(atan(1 / (p.asrShadowFactor + tan(rad(abs(latitude - decl))))))
            return angleTime(angle, t, counterClockwise: false)
        }

        // Dua iterasi dari tebakan awal (jam) cukup untuk ketelitian menit.
        var t: [Prayer: Double] = [.fajr: 5, .sunrise: 6, .dhuhr: 12, .asr: 13, .maghrib: 18, .isha: 18]
        for _ in 0..<2 {
            let f = t.mapValues { $0 / 24 }
            t = [
                .fajr: angleTime(p.fajrAngle, f[.fajr]!, counterClockwise: true),
                .sunrise: angleTime(0.833, f[.sunrise]!, counterClockwise: true),
                .dhuhr: midDay(f[.dhuhr]!),
                .asr: asrTime(f[.asr]!),
                .maghrib: angleTime(0.833, f[.maghrib]!, counterClockwise: false),
                .isha: angleTime(p.ishaAngle, f[.isha]!, counterClockwise: false),
            ]
        }

        var out: [Prayer: Int] = [:]
        for (prayer, hours) in t {
            let local = (hours + utcOffsetHours - longitude / 15) * 60
            if prayer == .sunrise {
                out[prayer] = Int((local - Double(p.ihtiyatMinutes)).rounded(.down))
            } else {
                out[prayer] = Int((local + Double(p.ihtiyatMinutes)).rounded(.up))
            }
        }
        out[.imsak] = (out[.fajr] ?? 0) - p.imsakMinutesBeforeFajr
        return out
    }

    /// Jadwal untuk tanggal `date` di zona waktu `timeZone`, sebagai `Date` absolut.
    static func schedule(for date: Date, latitude: Double, longitude: Double,
                         timeZone: TimeZone, parameters: PrayerParameters = .kemenag) -> [Prayer: Date] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.year, .month, .day], from: date)
        guard let y = c.year, let m = c.month, let d = c.day,
              let midnight = cal.date(from: DateComponents(year: y, month: m, day: d)) else { return [:] }
        let offset = Double(timeZone.secondsFromGMT(for: midnight.addingTimeInterval(12 * 3600))) / 3600
        let mins = minutes(year: y, month: m, day: d, latitude: latitude, longitude: longitude,
                           utcOffsetHours: offset, parameters: parameters)
        return mins.mapValues { midnight.addingTimeInterval(TimeInterval($0 * 60)) }
    }

    /// "04.11" (format jam Indonesia memakai titik).
    static func clock(_ minutes: Int) -> String {
        let m = ((minutes % 1440) + 1440) % 1440
        return String(format: "%02d.%02d", m / 60, m % 60)
    }

    // MARK: - Astronomi

    private static func rad(_ d: Double) -> Double { d * .pi / 180 }
    private static func deg(_ r: Double) -> Double { r * 180 / .pi }
    private static func fixAngle(_ a: Double) -> Double { a - 360 * (a / 360).rounded(.down) }
    private static func fixHour(_ h: Double) -> Double { h - 24 * (h / 24).rounded(.down) }

    private static func julian(_ year: Int, _ month: Int, _ day: Int) -> Double {
        var y = Double(year), m = Double(month)
        if m <= 2 { y -= 1; m += 12 }
        let a = (y / 100).rounded(.down)
        let b = 2 - a + (a / 4).rounded(.down)
        return (365.25 * (y + 4716)).rounded(.down) + (30.6001 * (m + 1)).rounded(.down) + Double(day) + b - 1524.5
    }

    private static func sunPosition(_ jd: Double) -> (declination: Double, equation: Double) {
        let d = jd - 2451545.0
        let g = fixAngle(357.529 + 0.98560028 * d)
        let q = fixAngle(280.459 + 0.98564736 * d)
        let l = fixAngle(q + 1.915 * sin(rad(g)) + 0.020 * sin(rad(2 * g)))
        let e = 23.439 - 0.00000036 * d
        let ra = deg(atan2(cos(rad(e)) * sin(rad(l)), cos(rad(l)))) / 15
        let eqt = q / 15 - fixHour(ra)
        let decl = deg(asin(sin(rad(e)) * sin(rad(l))))
        return (decl, eqt)
    }
}
