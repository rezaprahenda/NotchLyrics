import Foundation

// Logika murni cuaca (Open-Meteo), dites di Tests/WeatherTests.swift.

/// Kondisi cuaca saat ini.
struct WeatherNow: Equatable {
    let temperature: Double
    let code: Int
    let isDay: Bool
    /// Suhu & kode beberapa jam ke depan (jam berikutnya dulu).
    let nextHours: [(hour: Date, temperature: Double, code: Int)]

    static func == (a: WeatherNow, b: WeatherNow) -> Bool {
        a.temperature == b.temperature && a.code == b.code && a.isDay == b.isDay
            && a.nextHours.map(\.hour) == b.nextHours.map(\.hour)
            && a.nextHours.map(\.temperature) == b.nextHours.map(\.temperature)
    }

    var symbol: String { WeatherCore.symbol(code: code, isDay: isDay) }
    var summary: String { WeatherCore.summary(code: code) }
    var temperatureText: String { WeatherCore.degrees(temperature) }
}

enum WeatherCore {
    /// URL API Open-Meteo (gratis, tanpa kunci): kondisi sekarang + 6 jam ke depan.
    static func url(latitude: Double, longitude: Double) -> URL? {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        c?.queryItems = [
            .init(name: "latitude", value: String(format: "%.3f", latitude)),
            .init(name: "longitude", value: String(format: "%.3f", longitude)),
            .init(name: "current", value: "temperature_2m,weather_code,is_day"),
            .init(name: "hourly", value: "temperature_2m,weather_code"),
            .init(name: "forecast_hours", value: "7"),
            .init(name: "timezone", value: "auto"),
            .init(name: "timeformat", value: "unixtime"),
        ]
        return c?.url
    }

    private struct Response: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let weather_code: Int
            let is_day: Int
        }
        struct Hourly: Decodable {
            let time: [Double]
            let temperature_2m: [Double?]
            let weather_code: [Int?]
        }
        let current: Current
        let hourly: Hourly?
    }

    static func parse(_ data: Data, now: Date = Date()) -> WeatherNow? {
        guard let r = try? JSONDecoder().decode(Response.self, from: data) else { return nil }
        var hours: [(hour: Date, temperature: Double, code: Int)] = []
        if let h = r.hourly {
            for i in h.time.indices where i < h.temperature_2m.count && i < h.weather_code.count {
                let date = Date(timeIntervalSince1970: h.time[i])
                guard date > now, let t = h.temperature_2m[i], let c = h.weather_code[i] else { continue }
                hours.append((hour: date, temperature: t, code: c))
            }
        }
        return WeatherNow(temperature: r.current.temperature_2m, code: r.current.weather_code,
                          isDay: r.current.is_day == 1, nextHours: Array(hours.prefix(6)))
    }

    /// "27°" (dibulatkan; tanpa "-0").
    static func degrees(_ t: Double) -> String {
        let v = Int(t.rounded())
        return "\(v == 0 ? 0 : v)°"
    }

    /// SF Symbol untuk kode cuaca WMO.
    static func symbol(code: Int, isDay: Bool) -> String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
        case 61, 63, 66, 80, 81: return "cloud.rain.fill"
        case 65, 67, 82: return "cloud.heavyrain.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    static func summary(code: Int) -> String {
        switch code {
        case 0: return L("Cerah", "Clear")
        case 1, 2: return L("Cerah berawan", "Partly cloudy")
        case 3: return L("Berawan", "Cloudy")
        case 45, 48: return L("Berkabut", "Foggy")
        case 51, 53, 55, 56, 57: return L("Gerimis", "Drizzle")
        case 61, 63, 66, 80, 81: return L("Hujan", "Rain")
        case 65, 67, 82: return L("Hujan lebat", "Heavy rain")
        case 71, 73, 75, 77, 85, 86: return L("Salju", "Snow")
        case 95, 96, 99: return L("Hujan petir", "Thunderstorm")
        default: return L("Berawan", "Cloudy")
        }
    }

    /// Kalimat singkat untuk tooltip: "Hujan mulai ±16.00" jika hujan akan turun dalam beberapa jam.
    static func rainHint(_ w: WeatherNow, format: (Date) -> String) -> String? {
        let rainy: (Int) -> Bool = { (51...67).contains($0) || (80...82).contains($0) || (95...99).contains($0) }
        guard !rainy(w.code), let first = w.nextHours.first(where: { rainy($0.code) }) else { return nil }
        return L("Hujan mulai ±\(format(first.hour))", "Rain from about \(format(first.hour))")
    }
}
