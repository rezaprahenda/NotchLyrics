import Foundation

func weatherTests() {
    suite("WeatherCore") {
        let json = """
        {"current":{"time":1793200000,"temperature_2m":27.4,"weather_code":2,"is_day":0},
         "hourly":{"time":[1793196400,1793200000,1793203600,1793207200],
                   "temperature_2m":[28.0,27.4,26.9,null],
                   "weather_code":[2,2,61,63]}}
        """.data(using: .utf8)!
        let now = Date(timeIntervalSince1970: 1_793_200_000)
        let w = WeatherCore.parse(json, now: now)
        expect(w != nil, "JSON Open-Meteo terbaca")
        expectEqual(w?.temperatureText, "27°", "suhu dibulatkan")
        expectEqual(w?.isDay, false, "malam")
        expectEqual(w?.nextHours.count, 1, "hanya jam setelah sekarang & tanpa null")
        expectEqual(w?.symbol, "cloud.moon.fill", "ikon malam berawan")
        if let w {
            expectEqual(WeatherCore.rainHint(w, format: { _ in "22.00" }), L("Hujan mulai ±22.00", "Rain from about 22.00"),
                        "petunjuk hujan")
        }
        expect(WeatherCore.parse(Data("{}".utf8)) == nil, "JSON rusak → nil")
        expectEqual(WeatherCore.degrees(-0.4), "0°", "tanpa -0")
        expectEqual(WeatherCore.symbol(code: 95, isDay: true), "cloud.bolt.rain.fill", "badai")
        let url = WeatherCore.url(latitude: -6.2088, longitude: 106.8456)?.absoluteString ?? ""
        expect(url.contains("latitude=-6.209") && url.contains("longitude=106.846"), "koordinat di URL: \(url)")
    }
}
