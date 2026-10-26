import Foundation
import Combine
import Network

struct LyricLine: Identifiable, Equatable, Codable {
    let id: Int
    let time: Double
    let text: String
}

enum LyricsState: Equatable, Codable {
    case none
    case loading
    case synced([LyricLine])
    case plain([String])
    case instrumental
    case notFound

    var syncedLines: [LyricLine]? {
        if case .synced(let lines) = self { return lines }
        return nil
    }
}

enum TranslationStatus: Equatable {
    case idle
    case translating
    case done
    case failed(String)
}

/// Isi baris lirik di bawah notch (mode ringkas).
enum CompactLyricStyle: String, CaseIterable {
    case original
    case latin
    case translation
    case latinTranslation

    var title: String {
        switch self {
        case .original: return L("Teks asli", "Original")
        case .latin: return L("Latin (romanisasi)", "Latin (romanized)")
        case .translation: return L("Terjemahan", "Translation")
        case .latinTranslation: return L("Latin + terjemahan", "Latin + translation")
        }
    }

    var usesTranslation: Bool { self == .translation || self == .latinTranslation }
}

/// Satu hasil lirik dari LRCLIB yang bisa dipilih manual.
struct LyricCandidate: Identifiable, Equatable {
    let id: Int
    let title: String
    let artist: String
    let album: String
    let duration: Double
    let synced: String?
    let plain: String?
    let instrumental: Bool

    var hasSynced: Bool { !(synced ?? "").isEmpty }
}

private struct LRCLibResult: Decodable {
    let id: Int?
    let trackName: String?
    let artistName: String?
    let albumName: String?
    let duration: Double?
    let instrumental: Bool?
    let plainLyrics: String?
    let syncedLyrics: String?
}

/// Hasil satu kali mencari lirik di LRCLIB.
private enum FetchOutcome {
    case found(LyricsState)
    /// Server menjawab, tapi tidak ada lirik yang cocok.
    case missing
    /// Jaringan / server bermasalah — layak dicoba lagi nanti.
    case failed

    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}

/// Wadah hasil gabungan beberapa request paralel.
private final class ResultBox {
    private let lock = NSLock()
    private var items: [LRCLibResult] = []
    func append(_ more: [LRCLibResult]) { lock.lock(); items.append(contentsOf: more); lock.unlock() }
    var all: [LRCLibResult] { lock.lock(); defer { lock.unlock() }; return items }
}

/// Mengambil lirik dari LRCLIB (https://lrclib.net) — gratis, tanpa API key.
final class LyricsStore: ObservableObject {
    @Published private(set) var state: LyricsState = .none {
        didSet {
            requestTranslation()
            requestRomanization()
        }
    }

    /// Tampilkan baris sedikit lebih awal supaya terasa pas dengan vokal.
    static let lookahead: Double = 0.3

    /// Offset lirik untuk lagu saat ini (detik). Positif = lirik muncul lebih cepat.
    @Published private(set) var offset: Double = 0

    private static let offsetsDefaultsKey = "lyricOffsets"
    private static let overridesDefaultsKey = "lyricOverrides"

    // MARK: Romanisasi

    /// Tampilkan baris latin di mode lebar (tombol "Aa").
    @Published var romanizationEnabled: Bool = LyricsStore.storedBool("romanizationEnabled", true) {
        didSet { UserDefaults.standard.set(romanizationEnabled, forKey: "romanizationEnabled") }
    }
    /// id baris → teks latin (hanya baris non-latin).
    @Published private(set) var romanized: [Int: String] = [:]
    var hasRomanization: Bool { !romanized.isEmpty }
    private var romanizedSignature: String?

    // MARK: Gaya baris ringkas

    @Published var compactStyle: CompactLyricStyle =
        CompactLyricStyle(rawValue: UserDefaults.standard.string(forKey: "compactStyle") ?? "") ?? .latinTranslation {
        didSet {
            UserDefaults.standard.set(compactStyle.rawValue, forKey: "compactStyle")
            requestTranslation()
        }
    }

    // MARK: Terjemahan (lewat Translation framework macOS 15+)

    /// Bahasa target yang bisa dipilih di menu.
    static let translationTargets = ["id", "en", "ja", "ko", "zh-Hans", "es", "fr", "de"]

    @Published var translationTarget: String =
        UserDefaults.standard.string(forKey: "translationTarget") ?? (AppLanguage.isIndonesian ? "id" : "en") {
        didSet {
            guard translationTarget != oldValue else { return }
            UserDefaults.standard.set(translationTarget, forKey: "translationTarget")
            translations = [:]
            translationRequestedKey = nil
            translationStatus = .idle
            requestTranslation()
        }
    }

    /// Kunci cache terjemahan: lagu + bahasa target.
    var translationKey: String? { currentKey.map { "\($0)#\(translationTarget)" } }

    var alreadyTranslatedMessage: String {
        let name = languageName(translationTarget)
        return L("Lirik sudah berbahasa \(name)", "Lyrics are already in \(name)")
    }

    /// Tampilkan terjemahan di mode lebar (tombol "ID").
    @Published var translationEnabled: Bool = LyricsStore.storedBool("translationEnabled", false) {
        didSet {
            UserDefaults.standard.set(translationEnabled, forKey: "translationEnabled")
            requestTranslation()
        }
    }
    /// Terjemahan per baris: id baris lirik (atau indeks baris untuk lirik biasa) → teks terjemahan.
    @Published private(set) var translations: [Int: String] = [:]
    @Published private(set) var translationStatus: TranslationStatus = .idle
    /// Naik setiap kali perlu terjemahan baru; diamati oleh TranslationRunner.
    @Published private(set) var translationRequestID = 0

    /// Terjemahan dibutuhkan kalau tombol ID aktif ATAU baris ringkas memakai terjemahan.
    var wantsTranslation: Bool { translationEnabled || compactStyle.usesTranslation }

    private var translationRequestedKey: String?

    // MARK: Pilih lirik manual

    @Published var isPickerOpen = false {
        didSet {
            if isPickerOpen && candidates.isEmpty { searchCandidates() }
        }
    }
    @Published private(set) var candidates: [LyricCandidate] = []
    @Published private(set) var isSearchingCandidates = false
    /// Lagu ini memakai lirik yang dipilih manual.
    @Published private(set) var hasOverride = false

    // MARK: Internal

    /// Cache di memori, diisi dari disk saat app dibuka.
    private let disk = DiskCache()
    private lazy var cache: [String: LyricsState] = disk.lyrics
    private lazy var translationCache: [String: [Int: String]] = disk.translations
    private(set) var currentKey: String?
    private var currentTrack: Track?
    private var cancellable: AnyCancellable?

    // MARK: Coba lagi saat jaringan gagal

    private var retryKey: String?
    private var retryAttempts = 0
    private var retryWork: DispatchWorkItem?
    private static let maxTimedRetries = 3
    private let pathMonitor = NWPathMonitor()
    private var networkAvailable = true

    init() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let available = path.status == .satisfied
            DispatchQueue.main.async { self?.networkChanged(available) }
        }
        pathMonitor.start(queue: DispatchQueue(label: "notchlyrics.network", qos: .utility))
    }

    deinit {
        pathMonitor.cancel()
    }

    private static func storedBool(_ key: String, _ defaultValue: Bool) -> Bool {
        (UserDefaults.standard.object(forKey: key) as? Bool) ?? defaultValue
    }

    func bind(to player: PlayerMonitor) {
        cancellable = player.$track
            .removeDuplicates()
            .sink { [weak self] track in self?.load(for: track) }
    }

    /// Indeks baris yang sedang dinyanyikan, sudah memperhitungkan lookahead + offset.
    func currentIndex(in lines: [LyricLine], position: Double) -> Int? {
        Self.index(in: lines, at: position + Self.lookahead + offset)
    }

    /// Baris yang bisa diterjemahkan / diromanisasi: (id, teks).
    var translatableLines: [(Int, String)] {
        switch state {
        case .synced(let lines):
            return lines.filter { !$0.text.isEmpty }.map { ($0.id, $0.text) }
        case .plain(let lines):
            return lines.enumerated()
                .filter { !$0.element.trimmingCharacters(in: .whitespaces).isEmpty }
                .map { ($0.offset, $0.element) }
        default:
            return []
        }
    }

    // MARK: - Baris ringkas

    /// Baris ringkas dua tingkat (latin + terjemahan) hanya kalau terjemahannya ada.
    var compactIsDouble: Bool {
        compactStyle == .latinTranslation && !translations.isEmpty
    }

    func compactText(id: Int, original: String) -> (primary: String, secondary: String?) {
        let latin = romanized[id]
        let translated = translations[id]
        switch compactStyle {
        case .original:
            return (original, nil)
        case .latin:
            return (latin ?? original, nil)
        case .translation:
            return (translated ?? original, nil)
        case .latinTranslation:
            return (latin ?? original, compactIsDouble ? (translated ?? "") : nil)
        }
    }

    // MARK: - Simpan ke cache (memori + disk)

    private func storeLyrics(_ state: LyricsState?, for key: String) {
        cache[key] = state
        if state == nil { clearTranslations(forTrack: key) }
        disk.setLyrics(state, for: key)
    }

    private func storeTranslation(_ map: [Int: String], for translationKey: String) {
        translationCache[translationKey] = map
        disk.setTranslation(map, for: translationKey)
    }

    private func clearTranslations(forTrack key: String) {
        for k in Array(translationCache.keys) where k == key || k.hasPrefix(key + "#") {
            translationCache[k] = nil
        }
        disk.removeTranslations(forTrack: key)
    }

    /// Kosongkan cache lirik & terjemahan, lalu muat ulang lagu yang sedang diputar.
    /// Pilihan lirik manual dan offset tetap disimpan.
    func clearCache() {
        disk.clearAll()
        cache = [:]
        translationCache = [:]
        romanizedSignature = nil
        translationRequestedKey = nil
        translations = [:]
        let track = currentTrack
        currentKey = nil
        load(for: track)
    }

    // MARK: - Romanisasi

    private func requestRomanization() {
        let lines = translatableLines
        guard let key = currentKey, !lines.isEmpty else {
            if !romanized.isEmpty { romanized = [:] }
            romanizedSignature = nil
            return
        }
        // Tanda tangan lagu + isi lirik (lirik bisa berganti untuk lagu yang sama lewat pilih manual).
        let signature = "\(key)|\(lines.count)|\(lines.first?.1 ?? "")"
        guard signature != romanizedSignature else { return }
        romanizedSignature = signature
        if !romanized.isEmpty { romanized = [:] }

        DispatchQueue.global(qos: .userInitiated).async {
            let result = Romanizer.romanize(lines)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.romanizedSignature == signature else { return }
                self.romanized = result
            }
        }
    }

    // MARK: - Terjemahan

    /// Dipanggil saat lirik / lagu / pengaturan berubah.
    private func requestTranslation() {
        guard wantsTranslation, let key = translationKey, !translatableLines.isEmpty else {
            if !translations.isEmpty { translations = [:] }
            if translationStatus != .idle { translationStatus = .idle }
            translationRequestedKey = nil
            return
        }
        if let cached = translationCache[key] {
            if translations != cached { translations = cached }
            translationStatus = cached.isEmpty ? .failed(alreadyTranslatedMessage) : .done
            translationRequestedKey = key
            return
        }
        // Sudah diminta untuk lagu ini dan sedang diproses: jangan dobel.
        if translationRequestedKey == key, translationStatus == .translating { return }
        translationRequestedKey = key
        if !translations.isEmpty { translations = [:] }
        translationStatus = .idle
        translationRequestID += 1
    }

    func setTranslationStatus(_ status: TranslationStatus) {
        translationStatus = status
    }

    func applyTranslations(_ map: [Int: String], key: String) {
        guard key == translationKey, wantsTranslation else { return }
        storeTranslation(map, for: key)
        translations = map
        translationStatus = map.isEmpty ? .failed(alreadyTranslatedMessage) : .done
    }

    // MARK: - Offset (disimpan per lagu)

    func adjustOffset(by delta: Double) {
        setOffset(((offset + delta) * 10).rounded() / 10)
    }

    func resetOffset() {
        setOffset(0)
    }

    private func setOffset(_ value: Double) {
        offset = value
        guard let key = currentKey else { return }
        var stored = Self.storedOffsets()
        if value == 0 {
            stored.removeValue(forKey: key)
        } else {
            stored[key] = value
        }
        UserDefaults.standard.set(stored, forKey: Self.offsetsDefaultsKey)
    }

    private static func storedOffsets() -> [String: Double] {
        UserDefaults.standard.dictionary(forKey: offsetsDefaultsKey) as? [String: Double] ?? [:]
    }

    private static func storedOverrides() -> [String: Int] {
        UserDefaults.standard.dictionary(forKey: overridesDefaultsKey) as? [String: Int] ?? [:]
    }

    private static func saveOverrides(_ o: [String: Int]) {
        UserDefaults.standard.set(o, forKey: overridesDefaultsKey)
    }

    // MARK: - Loading

    func load(for track: Track?) {
        isPickerOpen = false
        candidates = []
        isSearchingCandidates = false
        retryWork?.cancel()
        retryWork = nil
        retryKey = nil
        retryAttempts = 0

        guard let track else {
            currentKey = nil
            currentTrack = nil
            hasOverride = false
            offset = 0
            state = .none
            return
        }
        let key = track.key
        currentKey = key
        currentTrack = track
        offset = Self.storedOffsets()[key] ?? 0
        let overrideID = Self.storedOverrides()[key]
        hasOverride = overrideID != nil

        if let cached = cache[key] {
            state = cached
            // state bisa saja sama dengan sebelumnya; pastikan terjemahan & romanisasi ikut lagu baru
            requestTranslation()
            requestRomanization()
            return
        }
        state = .loading

        if let overrideID {
            fetchByID(overrideID) { [weak self] result in
                if let result {
                    self?.finish(key, result)
                } else {
                    self?.automaticFetch(track, key: key)
                }
            }
        } else {
            automaticFetch(track, key: key)
        }
    }

    private func automaticFetch(_ track: Track, key: String) {
        fetchExact(track) { [weak self] exact in
            if case .found(let result) = exact {
                self?.finish(key, result)
                return
            }
            self?.fetchSearch(track) { search in
                switch search {
                case .found(let result):
                    self?.finish(key, result)
                case .missing where !exact.isFailure:
                    self?.finish(key, .notFound)
                default:
                    // Setidaknya satu request gagal karena jaringan: jangan anggap "tidak ada lirik".
                    self?.finishFailed(key, track)
                }
            }
        }
    }

    private func finish(_ key: String, _ result: LyricsState) {
        DispatchQueue.main.async {
            if result != .notFound { self.storeLyrics(result, for: key) }
            if self.currentKey == key { self.state = result }
        }
    }

    private func finishFailed(_ key: String, _ track: Track) {
        DispatchQueue.main.async {
            guard self.currentKey == key else { return }
            self.state = .notFound
            self.scheduleRetry(key)
        }
    }

    // MARK: - Coba lagi

    /// Coba lagi dengan jeda makin panjang (15, 30, 45 detik). Setelah itu hanya dicoba
    /// lagi saat jaringan tersambung kembali.
    private func scheduleRetry(_ key: String) {
        if retryKey != key {
            retryKey = key
            retryAttempts = 0
        }
        retryAttempts += 1
        retryWork?.cancel()
        retryWork = nil
        guard retryAttempts <= Self.maxTimedRetries else { return }
        let work = DispatchWorkItem { [weak self] in self?.retryNow() }
        retryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(retryAttempts) * 15, execute: work)
    }

    private func retryNow() {
        retryWork?.cancel()
        retryWork = nil
        guard let key = retryKey, key == currentKey, let t = currentTrack, state == .notFound else { return }
        state = .loading
        automaticFetch(t, key: key)
    }

    private func networkChanged(_ available: Bool) {
        let cameBack = available && !networkAvailable
        networkAvailable = available
        if cameBack { retryNow() }
    }

    // MARK: - Pilih lirik manual

    /// Cari beberapa kandidat lirik untuk lagu saat ini (judul+artis, dan judul saja).
    func searchCandidates() {
        guard let t = currentTrack, !isSearchingCandidates else { return }
        let key = t.key
        isSearchingCandidates = true
        candidates = []

        let queries: [[URLQueryItem]] = [
            [URLQueryItem(name: "q", value: "\(Self.clean(t.title)) \(Self.primaryArtist(t.artist))")],
            [URLQueryItem(name: "track_name", value: Self.clean(t.title))],
        ]
        let box = ResultBox()
        let group = DispatchGroup()
        for items in queries {
            guard let req = request("search", items) else { continue }
            group.enter()
            URLSession.shared.dataTask(with: req) { data, _, _ in
                if let data, let results = try? JSONDecoder().decode([LRCLibResult].self, from: data) {
                    box.append(results)
                }
                group.leave()
            }.resume()
        }

        group.notify(queue: .main) { [weak self] in
            guard let self, self.currentKey == key else { return }
            var seen = Set<Int>()
            let list: [LyricCandidate] = box.all.compactMap { r in
                guard let id = r.id, seen.insert(id).inserted else { return nil }
                let hasAny = !(r.syncedLyrics ?? "").isEmpty || !(r.plainLyrics ?? "").isEmpty || r.instrumental == true
                guard hasAny else { return nil }
                return LyricCandidate(id: id,
                                      title: r.trackName ?? "?",
                                      artist: r.artistName ?? "",
                                      album: r.albumName ?? "",
                                      duration: r.duration ?? 0,
                                      synced: r.syncedLyrics,
                                      plain: r.plainLyrics,
                                      instrumental: r.instrumental == true)
            }
            // Urutkan: yang tersinkron dulu, lalu yang durasinya paling dekat dengan lagu.
            let target = t.duration
            self.candidates = Array(list.sorted { a, b in
                if a.hasSynced != b.hasSynced { return a.hasSynced }
                return abs(a.duration - target) < abs(b.duration - target)
            }.prefix(25))
            self.isSearchingCandidates = false
        }
    }

    /// Pakai kandidat ini untuk lagu saat ini, dan ingat pilihannya.
    func choose(_ c: LyricCandidate) {
        guard let key = currentKey else { return }
        var o = Self.storedOverrides()
        o[key] = c.id
        Self.saveOverrides(o)
        hasOverride = true

        let newState = Self.state(synced: c.synced, plain: c.plain, instrumental: c.instrumental) ?? .notFound
        if newState != .notFound { storeLyrics(newState, for: key) }
        clearTranslations(forTrack: key)
        romanizedSignature = nil
        isPickerOpen = false
        state = newState
    }

    /// Hapus pilihan manual dan cari ulang lirik secara otomatis.
    func resetToAutomatic() {
        guard let key = currentKey, let t = currentTrack else { return }
        var o = Self.storedOverrides()
        o.removeValue(forKey: key)
        Self.saveOverrides(o)
        hasOverride = false
        storeLyrics(nil, for: key)
        romanizedSignature = nil
        isPickerOpen = false
        state = .loading
        automaticFetch(t, key: key)
    }

    // MARK: - Network

    private func request(_ path: String, _ items: [URLQueryItem]) -> URLRequest? {
        guard var c = URLComponents(string: "https://lrclib.net/api/\(path)") else { return nil }
        if !items.isEmpty { c.queryItems = items }
        guard let url = c.url else { return nil }
        var r = URLRequest(url: url, timeoutInterval: 10)
        r.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        return r
    }

    /// Versi dibaca dari Info.plist supaya tidak perlu diubah manual tiap rilis.
    private static let userAgent: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        return "NotchLyrics/\(version) (https://github.com/rezaprahenda/NotchLyrics)"
    }()

    /// 404 = lirik memang tidak ada. Status lain (5xx, 429) atau tanpa respons = gagal sementara.
    private static func outcome(_ resp: URLResponse?, _ error: Error?) -> FetchOutcome? {
        guard error == nil, let status = (resp as? HTTPURLResponse)?.statusCode else { return .failed }
        if status == 404 { return .missing }
        if status != 200 { return .failed }
        return nil // 200: lanjut decode
    }

    private func fetchByID(_ id: Int, done: @escaping (LyricsState?) -> Void) {
        guard let req = request("get/\(id)", []) else { return done(nil) }
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            guard let data,
                  (resp as? HTTPURLResponse)?.statusCode == 200,
                  let r = try? JSONDecoder().decode(LRCLibResult.self, from: data)
            else { return done(nil) }
            done(Self.state(from: r))
        }.resume()
    }

    /// Pencarian presisi: judul + artis + album + durasi.
    private func fetchExact(_ t: Track, done: @escaping (FetchOutcome) -> Void) {
        var items = [
            URLQueryItem(name: "track_name", value: t.title),
            URLQueryItem(name: "artist_name", value: t.artist),
        ]
        if !t.album.isEmpty { items.append(URLQueryItem(name: "album_name", value: t.album)) }
        if t.duration > 0 { items.append(URLQueryItem(name: "duration", value: String(Int(t.duration.rounded())))) }
        guard let req = request("get", items) else { return done(.missing) }

        URLSession.shared.dataTask(with: req) { data, resp, error in
            if let early = Self.outcome(resp, error) { return done(early) }
            guard let data, let r = try? JSONDecoder().decode(LRCLibResult.self, from: data) else {
                return done(.failed)
            }
            done(Self.state(from: r).map(FetchOutcome.found) ?? .missing)
        }.resume()
    }

    /// Cadangan: cari dengan judul yang sudah dibersihkan ("- Remastered", "(feat. ...)", dst).
    /// Hanya hasil yang durasinya dekat yang dipakai, supaya tidak menampilkan lirik lagu lain.
    private func fetchSearch(_ t: Track, done: @escaping (FetchOutcome) -> Void) {
        let items = [
            URLQueryItem(name: "track_name", value: Self.clean(t.title)),
            URLQueryItem(name: "artist_name", value: Self.primaryArtist(t.artist)),
        ]
        guard let req = request("search", items) else { return done(.missing) }

        URLSession.shared.dataTask(with: req) { data, resp, error in
            if let early = Self.outcome(resp, error) { return done(early) }
            guard let data, let results = try? JSONDecoder().decode([LRCLibResult].self, from: data) else {
                return done(.failed)
            }

            // Durasi tidak diketahui → terpaksa percaya hasil pencarian; selain itu wajib dekat.
            let pool = t.duration <= 0 ? results : results.filter { r in
                guard let d = r.duration else { return false }
                return abs(d - t.duration) <= 4
            }
            let best = pool.first { !($0.syncedLyrics ?? "").isEmpty }
                ?? pool.first { !($0.plainLyrics ?? "").isEmpty }
                ?? pool.first
            done(best.flatMap(Self.state(from:)).map(FetchOutcome.found) ?? .missing)
        }.resume()
    }

    private static func state(from r: LRCLibResult) -> LyricsState? {
        state(synced: r.syncedLyrics, plain: r.plainLyrics, instrumental: r.instrumental == true)
    }

    private static func state(synced: String?, plain: String?, instrumental: Bool) -> LyricsState? {
        if let s = synced, !s.isEmpty {
            let lines = parseLRC(s)
            if !lines.isEmpty { return .synced(lines) }
        }
        if let p = plain, !p.isEmpty {
            return .plain(p.components(separatedBy: .newlines))
        }
        if instrumental { return .instrumental }
        return nil
    }

    // MARK: - Helpers

    static func clean(_ title: String) -> String {
        var t = title
        if let r = t.range(of: " - ") { t = String(t[..<r.lowerBound]) }
        t = t.replacingOccurrences(
            of: #"\s*[\(\[](feat\.|ft\.|with |from |remaster)[^\)\]]*[\)\]]"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        return t.trimmingCharacters(in: .whitespaces)
    }

    static func primaryArtist(_ a: String) -> String {
        a.components(separatedBy: CharacterSet(charactersIn: ",&"))
            .first?
            .trimmingCharacters(in: .whitespaces) ?? a
    }

    /// Parse format LRC: "[01:23.45] teks". Satu baris bisa punya beberapa timestamp.
    static func parseLRC(_ s: String) -> [LyricLine] {
        guard let regex = try? NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{1,2}(?:[.:]\d{1,3})?)\]"#) else { return [] }
        var out: [(Double, String)] = []
        for raw in s.components(separatedBy: .newlines) {
            let ns = raw as NSString
            let matches = regex.matches(in: raw, range: NSRange(location: 0, length: ns.length))
            guard let last = matches.last else { continue }
            let text = ns.substring(from: last.range.location + last.range.length)
                .trimmingCharacters(in: .whitespaces)
            for m in matches {
                let minutes = Double(ns.substring(with: m.range(at: 1))) ?? 0
                let seconds = Double(ns.substring(with: m.range(at: 2)).replacingOccurrences(of: ":", with: ".")) ?? 0
                out.append((minutes * 60 + seconds, text))
            }
        }
        return out
            .sorted { $0.0 < $1.0 }
            .enumerated()
            .map { LyricLine(id: $0.offset, time: $0.element.0, text: $0.element.1) }
    }

    /// Indeks baris terakhir yang waktunya <= posisi saat ini (binary search).
    static func index(in lines: [LyricLine], at time: Double) -> Int? {
        var lo = 0, hi = lines.count - 1
        var ans: Int?
        while lo <= hi {
            let mid = (lo + hi) / 2
            if lines[mid].time <= time {
                ans = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return ans
    }
}
