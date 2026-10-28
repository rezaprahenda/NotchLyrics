import Foundation
import Combine
import CoreLocation

/// Cuaca kecil di kepala panel. Lokasi memakai lokasi modul Salat (otomatis atau kota pilihan),
/// jadi tidak ada izin baru. Data dari Open-Meteo, diperbarui tiap 30 menit.
final class WeatherModule: ObservableObject {
    static let shared = WeatherModule()

    @Published var enabled: Bool = Defaults.bool("weather.enabled", true) {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "weather.enabled")
            if enabled { refresh() } else { current = nil }
        }
    }
    @Published private(set) var current: WeatherNow?

    /// Diisi AppDelegate: koordinat yang sedang dipakai modul Salat.
    var locate: (() -> (lat: Double, lon: Double)?)?

    private var timer: Timer?
    private var lastFetch: Date?
    private var lastCoordinate: (lat: Double, lon: Double)?
    private var inFlight = false

    func start() {
        timer?.invalidate()
        let t = Timer(timeInterval: 30 * 60, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        refresh()
    }

    /// Dipanggil saat panel dibuka: ambil ulang jika data sudah lama atau lokasi berpindah.
    func refreshIfStale() {
        guard enabled else { return }
        let old = lastFetch.map { Date().timeIntervalSince($0) > 20 * 60 } ?? true
        var moved = false
        if let now = locate?(), let last = lastCoordinate {
            moved = CLLocation(latitude: now.lat, longitude: now.lon)
                .distance(from: CLLocation(latitude: last.lat, longitude: last.lon)) > 5_000
        }
        if old || moved || current == nil { refresh() }
    }

    func refresh() {
        guard enabled, !inFlight, let c = locate?(), let url = WeatherCore.url(latitude: c.lat, longitude: c.lon) else { return }
        inFlight = true
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("popocu", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            let parsed = data.flatMap { WeatherCore.parse($0) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight = false
                if let parsed {
                    self.current = parsed
                    self.lastFetch = Date()
                    self.lastCoordinate = c
                }
            }
        }.resume()
    }
}
