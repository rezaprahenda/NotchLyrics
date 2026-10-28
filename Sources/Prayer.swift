import Foundation
import AppKit
import Combine
import CoreLocation
import CoreAudio

/// Kota untuk mode lokasi manual.
struct PrayerCity: Identifiable, Hashable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let timeZoneID: String

    static let all: [PrayerCity] = [
        .init(id: "banda-aceh", name: "Banda Aceh", latitude: 5.5483, longitude: 95.3238, timeZoneID: "Asia/Jakarta"),
        .init(id: "medan", name: "Medan", latitude: 3.5952, longitude: 98.6722, timeZoneID: "Asia/Jakarta"),
        .init(id: "padang", name: "Padang", latitude: -0.9471, longitude: 100.4172, timeZoneID: "Asia/Jakarta"),
        .init(id: "pekanbaru", name: "Pekanbaru", latitude: 0.5071, longitude: 101.4478, timeZoneID: "Asia/Jakarta"),
        .init(id: "palembang", name: "Palembang", latitude: -2.9761, longitude: 104.7754, timeZoneID: "Asia/Jakarta"),
        .init(id: "bandar-lampung", name: "Bandar Lampung", latitude: -5.3971, longitude: 105.2668, timeZoneID: "Asia/Jakarta"),
        .init(id: "jakarta", name: "Jakarta", latitude: -6.1667, longitude: 106.8167, timeZoneID: "Asia/Jakarta"),
        .init(id: "bandung", name: "Bandung", latitude: -6.9175, longitude: 107.6191, timeZoneID: "Asia/Jakarta"),
        .init(id: "semarang", name: "Semarang", latitude: -6.9667, longitude: 110.4167, timeZoneID: "Asia/Jakarta"),
        .init(id: "yogyakarta", name: "Yogyakarta", latitude: -7.7956, longitude: 110.3695, timeZoneID: "Asia/Jakarta"),
        .init(id: "surabaya", name: "Surabaya", latitude: -7.2575, longitude: 112.7521, timeZoneID: "Asia/Jakarta"),
        .init(id: "malang", name: "Malang", latitude: -7.9666, longitude: 112.6326, timeZoneID: "Asia/Jakarta"),
        .init(id: "pontianak", name: "Pontianak", latitude: -0.0263, longitude: 109.3425, timeZoneID: "Asia/Jakarta"),
        .init(id: "denpasar", name: "Denpasar", latitude: -8.6705, longitude: 115.2126, timeZoneID: "Asia/Makassar"),
        .init(id: "mataram", name: "Mataram", latitude: -8.5833, longitude: 116.1167, timeZoneID: "Asia/Makassar"),
        .init(id: "banjarmasin", name: "Banjarmasin", latitude: -3.3186, longitude: 114.5944, timeZoneID: "Asia/Makassar"),
        .init(id: "balikpapan", name: "Balikpapan", latitude: -1.2379, longitude: 116.8529, timeZoneID: "Asia/Makassar"),
        .init(id: "samarinda", name: "Samarinda", latitude: -0.5022, longitude: 117.1536, timeZoneID: "Asia/Makassar"),
        .init(id: "makassar", name: "Makassar", latitude: -5.1477, longitude: 119.4327, timeZoneID: "Asia/Makassar"),
        .init(id: "manado", name: "Manado", latitude: 1.4748, longitude: 124.8421, timeZoneID: "Asia/Makassar"),
        .init(id: "kupang", name: "Kupang", latitude: -10.1772, longitude: 123.6070, timeZoneID: "Asia/Makassar"),
        .init(id: "ambon", name: "Ambon", latitude: -3.6954, longitude: 128.1814, timeZoneID: "Asia/Jayapura"),
        .init(id: "jayapura", name: "Jayapura", latitude: -2.5337, longitude: 140.7181, timeZoneID: "Asia/Jayapura"),
    ]
}

enum PrayerLocationMode: String, CaseIterable {
    case automatic, manual
}

enum RamadanMode: String, CaseIterable {
    case automatic, on, off

    var title: String {
        switch self {
        case .automatic: return L("Otomatis (kalender Hijriah)", "Automatic (Hijri calendar)")
        case .on: return L("Selalu aktif", "Always on")
        case .off: return L("Mati", "Off")
        }
    }
}

enum AdhanSound: String, CaseIterable {
    case off, system, file

    var title: String {
        switch self {
        case .off: return L("Tanpa suara", "Silent")
        case .system: return L("Bunyi sistem", "System sound")
        case .file: return L("File audio sendiri…", "Your own audio file…")
        }
    }
}

enum PrayerEvent {
    /// Waktu salat masuk.
    case arrived(Prayer)
    /// Pengingat sebelum waktu salat.
    case upcoming(Prayer, minutes: Int)
}

/// Modul jadwal salat & adzan. Dihitung offline dari lokasi; timer hanya ke waktu berikutnya.
final class PrayerModule: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var enabled: Bool = Defaults.bool("prayer.enabled", false) {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "prayer.enabled")
            if enabled { refreshLocation() }
            reschedule()
        }
    }
    @Published var locationMode: PrayerLocationMode =
        PrayerLocationMode(rawValue: UserDefaults.standard.string(forKey: "prayer.locationMode") ?? "") ?? .automatic {
        didSet {
            UserDefaults.standard.set(locationMode.rawValue, forKey: "prayer.locationMode")
            refreshLocation()
            reschedule()
        }
    }
    @Published var manualCityID: String = UserDefaults.standard.string(forKey: "prayer.city") ?? "jakarta" {
        didSet { UserDefaults.standard.set(manualCityID, forKey: "prayer.city"); reschedule() }
    }
    @Published var preAlerts: Bool = Defaults.bool("prayer.preAlerts", true) {
        didSet { UserDefaults.standard.set(preAlerts, forKey: "prayer.preAlerts"); reschedule() }
    }
    @Published var adhanSound: AdhanSound =
        AdhanSound(rawValue: UserDefaults.standard.string(forKey: "prayer.sound") ?? "") ?? .system {
        didSet { UserDefaults.standard.set(adhanSound.rawValue, forKey: "prayer.sound") }
    }
    @Published var adhanFilePath: String = UserDefaults.standard.string(forKey: "prayer.soundFile") ?? "" {
        didSet { UserDefaults.standard.set(adhanFilePath, forKey: "prayer.soundFile") }
    }
    @Published var pauseMusicAtAdhan: Bool = Defaults.bool("prayer.pauseMusic", false) {
        didSet { UserDefaults.standard.set(pauseMusicAtAdhan, forKey: "prayer.pauseMusic") }
    }
    @Published var pausePomodoroAtAdhan: Bool = Defaults.bool("prayer.pausePomodoro", true) {
        didSet { UserDefaults.standard.set(pausePomodoroAtAdhan, forKey: "prayer.pausePomodoro") }
    }
    @Published var ramadanMode: RamadanMode =
        RamadanMode(rawValue: UserDefaults.standard.string(forKey: "prayer.ramadan") ?? "") ?? .automatic {
        didSet { UserDefaults.standard.set(ramadanMode.rawValue, forKey: "prayer.ramadan") }
    }

    /// Jadwal hari ini & besok (untuk Subuh setelah Isya).
    @Published private(set) var today: [Prayer: Date] = [:]
    @Published private(set) var tomorrow: [Prayer: Date] = [:]
    /// Nama tempat yang dipakai ("Jakarta", atau hasil lokasi otomatis).
    @Published private(set) var placeName = ""
    @Published private(set) var locationDenied = false
    /// Berdetak tiap 30 detik selama modul aktif, untuk hitung mundur & aturan prioritas.
    @Published private(set) var now = Date()

    var onEvent: ((PrayerEvent) -> Void)?

    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var timers: [Timer] = []
    private var tickTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var sound: NSSound?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer

        // Hari berganti, Mac bangun dari tidur, atau zona waktu berubah → hitung ulang.
        let ws = NSWorkspace.shared.notificationCenter
        observers.append(ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refreshLocation()
            self?.reschedule()
        })
        for name in [Notification.Name.NSCalendarDayChanged, Notification.Name.NSSystemTimeZoneDidChange] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.reschedule()
            })
        }
        if enabled { refreshLocation() }
        reschedule()
    }

    // MARK: - Lokasi

    private var savedLocation: (lat: Double, lon: Double)? {
        let d = UserDefaults.standard
        guard d.object(forKey: "prayer.lat") != nil else { return nil }
        return (d.double(forKey: "prayer.lat"), d.double(forKey: "prayer.lon"))
    }

    private var manualCity: PrayerCity {
        PrayerCity.all.first { $0.id == manualCityID } ?? PrayerCity.all.first { $0.id == "jakarta" }!
    }

    /// Koordinat & zona waktu yang dipakai saat ini.
    private var place: (lat: Double, lon: Double, tz: TimeZone, name: String)? {
        switch locationMode {
        case .manual:
            let c = manualCity
            return (c.latitude, c.longitude, TimeZone(identifier: c.timeZoneID) ?? .current, c.name)
        case .automatic:
            guard let saved = savedLocation else { return nil }
            return (saved.lat, saved.lon, .current, UserDefaults.standard.string(forKey: "prayer.place") ?? "")
        }
    }

    /// Koordinat yang dipakai (juga untuk cuaca).
    var coordinate: (lat: Double, lon: Double)? { place.map { ($0.lat, $0.lon) } }

    /// Arah kiblat dari lokasi yang dipakai (derajat dari utara).
    var qibla: Double? {
        place.map { PrayerCalc.qibla(latitude: $0.lat, longitude: $0.lon) }
    }

    func refreshLocation() {
        guard enabled, locationMode == .automatic else { return }
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            locationDenied = true
        default:
            locationDenied = false
            locationManager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .denied, .restricted:
            locationDenied = true
        case .notDetermined:
            break
        default:
            locationDenied = false
            if enabled && locationMode == .automatic { manager.requestLocation() }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let d = UserDefaults.standard
        let moved = savedLocation.map {
            CLLocation(latitude: $0.lat, longitude: $0.lon).distance(from: loc) > 5_000
        } ?? true
        d.set(loc.coordinate.latitude, forKey: "prayer.lat")
        d.set(loc.coordinate.longitude, forKey: "prayer.lon")
        if moved || d.string(forKey: "prayer.place") == nil {
            geocoder.reverseGeocodeLocation(loc) { [weak self] marks, _ in
                let name = marks?.first.flatMap { $0.locality ?? $0.subAdministrativeArea ?? $0.administrativeArea }
                DispatchQueue.main.async {
                    if let name { UserDefaults.standard.set(name, forKey: "prayer.place") }
                    self?.reschedule()
                }
            }
        }
        reschedule()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        NSLog("popocu: lokasi gagal: %@", error.localizedDescription)
    }

    // MARK: - Jadwal

    func reschedule() {
        timers.forEach { $0.invalidate() }
        timers = []
        tickTimer?.invalidate()
        tickTimer = nil

        guard enabled, let place else {
            today = [:]
            tomorrow = [:]
            placeName = place?.name ?? ""
            return
        }
        placeName = place.name
        let date = Date()
        today = PrayerCalc.schedule(for: date, latitude: place.lat, longitude: place.lon, timeZone: place.tz)
        tomorrow = PrayerCalc.schedule(for: date.addingTimeInterval(86_400), latitude: place.lat,
                                       longitude: place.lon, timeZone: place.tz)
        now = date

        // Waktu yang sudah lewat diabaikan oleh schedule(); Subuh & Imsak besok ikut dijadwalkan
        // untuk malam hari. Tengah malam semuanya dijadwalkan ulang (NSCalendarDayChanged).
        for (prayer, time) in today { schedule(prayer, at: time) }
        for (prayer, time) in tomorrow where prayer == .fajr || prayer == .imsak { schedule(prayer, at: time) }

        let tick = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.now = Date() }
        RunLoop.main.add(tick, forMode: .common)
        tickTimer = tick
    }

    private func schedule(_ prayer: Prayer, at time: Date) {
        let nowDate = Date()
        if prayer.isObligatory, time > nowDate {
            add(at: time) { [weak self] in self?.arrived(prayer) }
            if preAlerts {
                for minutes in [15, 5] {
                    let at = time.addingTimeInterval(TimeInterval(-minutes * 60))
                    if at > nowDate { add(at: at) { [weak self] in self?.onEvent?(.upcoming(prayer, minutes: minutes)) } }
                }
            }
        }
        if prayer == .imsak, isRamadan, time > nowDate {
            add(at: time) { [weak self] in self?.onEvent?(.arrived(.imsak)) }
        }
    }

    private func add(at date: Date, _ action: @escaping () -> Void) {
        let t = Timer(fire: date, interval: 0, repeats: false) { _ in action() }
        RunLoop.main.add(t, forMode: .common)
        timers.append(t)
    }

    private func arrived(_ prayer: Prayer) {
        now = Date()
        playAdhan()
        onEvent?(.arrived(prayer))
    }

    // MARK: - Status untuk tampilan & prioritas

    /// Waktu salat wajib berikutnya (bisa Subuh besok).
    func next(after date: Date = Date()) -> (prayer: Prayer, time: Date)? {
        let candidates = today.filter { $0.key.isObligatory && $0.value > date }
            .min { $0.value < $1.value }
        if let c = candidates { return (c.key, c.value) }
        if let fajr = tomorrow[.fajr] { return (.fajr, fajr) }
        return nil
    }

    /// Waktu salat wajib terakhir yang sudah masuk hari ini.
    func last(before date: Date = Date()) -> (prayer: Prayer, time: Date)? {
        today.filter { $0.key.isObligatory && $0.value <= date }
            .max { $0.value < $1.value }
            .map { ($0.key, $0.value) }
    }

    func minutesToNext(at date: Date = Date()) -> Double? {
        next(after: date).map { $0.time.timeIntervalSince(date) / 60 }
    }

    func minutesSinceLast(at date: Date = Date()) -> Double? {
        last(before: date).map { date.timeIntervalSince($0.time) / 60 }
    }

    var isRamadan: Bool {
        switch ramadanMode {
        case .on: return true
        case .off: return false
        case .automatic:
            return Calendar(identifier: .islamicUmmAlQura).component(.month, from: Date()) == 9
        }
    }

    /// "4 Jumadilawal 1448 H".
    var hijriDate: String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .islamicUmmAlQura)
        f.locale = Locale(identifier: AppLanguage.isIndonesian ? "id" : "en")
        f.dateFormat = "d MMMM y"
        return f.string(from: Date()) + " H"
    }

    func timeText(_ date: Date?) -> String {
        guard let date else { return "–" }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = place?.tz ?? .current
        let c = cal.dateComponents([.hour, .minute], from: date)
        return PrayerCalc.clock((c.hour ?? 0) * 60 + (c.minute ?? 0))
    }

    // MARK: - Adzan

    func playAdhan() {
        guard adhanSound != .off else { return }
        // Jangan berbunyi saat mikrofon dipakai (rapat / telepon): cukup peek visual.
        guard !MicrophoneMonitor.isInUse() else { return }
        sound?.stop()
        switch adhanSound {
        case .off:
            return
        case .system:
            sound = NSSound(named: "Submarine")
        case .file:
            sound = adhanFilePath.isEmpty ? nil : NSSound(contentsOfFile: adhanFilePath, byReference: true)
        }
        sound?.play()
    }

    func stopAdhan() {
        sound?.stop()
    }
}

/// Apakah mikrofon bawaan sedang dipakai app lain (rapat, telepon, rekaman).
enum MicrophoneMonitor {
    static func isInUse() -> Bool {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID) == noErr,
              deviceID != 0 else { return false }
        var running = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &running) == noErr else { return false }
        return running != 0
    }
}
