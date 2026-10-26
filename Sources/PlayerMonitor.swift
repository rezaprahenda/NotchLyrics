import AppKit
import Combine
import SwiftUI

enum MusicSource: String, CaseIterable {
    case spotify, music

    var bundleID: String {
        switch self {
        case .spotify: return "com.spotify.client"
        case .music: return "com.apple.Music"
        }
    }

    var displayName: String {
        switch self {
        case .spotify: return "Spotify"
        case .music: return "Apple Music"
        }
    }
}

struct Track: Equatable {
    let source: MusicSource
    let id: String
    let title: String
    let artist: String
    let album: String
    let duration: Double // detik

    var key: String { "\(source.rawValue)|\(id)|\(title)|\(artist)" }
}

enum RepeatMode: String {
    case off, all, one
}

private struct Snapshot {
    let isPlaying: Bool
    let track: Track
    let position: Double
    let artworkURL: String
    let volume: Double?
    let shuffle: Bool?
    let repeatMode: RepeatMode?
}

/// Hasil satu kali menjalankan osascript.
private struct OSAResult {
    let output: String?
    let error: String?
    let errorCode: Int?
}

/// Membaca lagu yang sedang diputar dari Spotify / Apple Music lewat `/usr/bin/osascript`.
final class PlayerMonitor: ObservableObject {
    @Published private(set) var track: Track?
    @Published private(set) var isPlaying = false
    @Published private(set) var artwork: NSImage? {
        didSet { artworkColor = artwork?.accentColor().map { Color(nsColor: $0) } }
    }
    /// Warna aksen dari cover (nil kalau cover tidak ada / hampir abu-abu).
    @Published private(set) var artworkColor: Color?
    @Published private(set) var permissionDenied: MusicSource?
    @Published private(set) var lastError: String?
    /// Volume app musik (0–100), bukan volume sistem.
    @Published private(set) var volume: Double?
    /// Status favorit lagu (hanya Apple Music; nil = tidak didukung).
    @Published private(set) var isFavorite: Bool?

    @Published private(set) var shuffle: Bool?
    @Published private(set) var repeatMode: RepeatMode?

    /// Sleep timer: berhenti pada waktu tertentu, atau saat lagu yang sedang diputar selesai.
    @Published private(set) var sleepUntil: Date?
    @Published private(set) var sleepAtTrackEnd = false
    private var sleepTimer: Timer?
    private var sleepTrackKey: String?

    private var volumeHoldUntil = Date.distantPast
    private var modeHoldUntil = Date.distantPast
    private var volumeWork: DispatchWorkItem?
    /// Nama properti favorit di AppleScript Music: "favorited" (baru) atau "loved" (lama).
    private var favoriteTerm: String?

    private var basePosition: Double = 0
    private var baseDate = Date()
    private var timer: Timer?
    private var artworkKey: String?
    private var isPolling = false
    private let queue = DispatchQueue(label: "notchlyrics.osascript", qos: .userInitiated)

    /// Posisi lagu saat ini (diinterpolasi di antara polling supaya lirik mulus).
    var position: Double {
        guard let track else { return 0 }
        let p = isPlaying ? basePosition + Date().timeIntervalSince(baseDate) : basePosition
        let clamped = max(p, 0)
        return track.duration > 0 ? min(clamped, track.duration) : clamped
    }

    /// Jeda polling rutin. Perubahan lagu/status sudah ditangkap instan lewat sinyal dari
    /// Spotify & Music, jadi polling hanya untuk mengoreksi posisi dan volume/shuffle/repeat.
    /// Tiap poll menjalankan proses osascript baru, jadi dibuat jarang demi baterai.
    private static let pollIntervalPlaying: TimeInterval = 5
    private static let pollIntervalIdle: TimeInterval = 10
    private var nextPollAt = Date.distantPast
    private var needsRepoll = false
    private var signalObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []

    func start() {
        poll()

        // Detak tiap detik, tapi poll hanya kalau sudah jatuh tempo.
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, Date() >= self.nextPollAt else { return }
            self.poll()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        // Sinyal yang dikirim Spotify & Music setiap kali lagu, play/pause, atau posisi berubah.
        let center = DistributedNotificationCenter.default()
        for name in ["com.spotify.client.PlaybackStateChanged", "com.apple.Music.playerInfo"] {
            let o = center.addObserver(forName: NSNotification.Name(name), object: nil, queue: .main) { [weak self] _ in
                self?.pollSoon()
            }
            signalObservers.append(o)
        }

        // App musik dibuka / ditutup → cek segera.
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            let o = ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard let id = app?.bundleIdentifier,
                      MusicSource.allCases.contains(where: { $0.bundleID == id })
                else { return }
                self?.pollSoon()
            }
            workspaceObservers.append(o)
        }
    }

    /// Poll secepatnya; kalau sedang ada poll berjalan, ulangi setelah selesai.
    private func pollSoon() {
        if isPolling {
            needsRepoll = true
        } else {
            poll()
        }
    }

    // MARK: - Kontrol

    func playPause() {
        let p = position
        isPlaying.toggle()
        basePosition = p
        baseDate = Date()
        send("playpause")
    }

    func next() { send("next track") }
    func previous() { send("previous track") }

    /// Lompat ke detik tertentu (dipakai saat baris lirik diklik).
    func seek(to seconds: Double) {
        guard track != nil else { return }
        let target = max(0, seconds)
        // Posisi tidak @Published; beri tahu view supaya baris lirik ikut pindah walau sedang pause.
        objectWillChange.send()
        basePosition = target
        baseDate = Date()
        // String(format:) selalu pakai titik desimal, sesuai sintaks AppleScript.
        send(String(format: "set player position to %.2f", target))
    }

    /// Atur volume app (0–100). Dikirim dengan jeda kecil supaya tidak membanjiri osascript saat slider digeser.
    func setVolume(_ value: Double) {
        let v = min(max(value, 0), 100)
        volume = v
        volumeHoldUntil = Date().addingTimeInterval(1.5) // abaikan hasil polling sebentar
        volumeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.send("set sound volume to \(Int(v.rounded()))", pollAfter: false)
        }
        volumeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    // MARK: - Shuffle & repeat

    func toggleShuffle() {
        guard let source = track?.source, let s = shuffle else { return }
        shuffle = !s
        modeHoldUntil = Date().addingTimeInterval(1.5)
        switch source {
        case .spotify: send("set shuffling to \(!s)", pollAfter: false)
        case .music: send("set shuffle enabled to \(!s)", pollAfter: false)
        }
    }

    /// Spotify: off ↔ all (AppleScript Spotify tidak bisa repeat-one). Music: off → all → one → off.
    func cycleRepeat() {
        guard let source = track?.source, let r = repeatMode else { return }
        let next: RepeatMode
        switch (source, r) {
        case (.spotify, .off): next = .all
        case (.spotify, _): next = .off
        case (.music, .off): next = .all
        case (.music, .all): next = .one
        case (.music, .one): next = .off
        }
        repeatMode = next
        modeHoldUntil = Date().addingTimeInterval(1.5)
        switch source {
        case .spotify: send("set repeating to \(next != .off)", pollAfter: false)
        case .music: send("set song repeat to \(next.rawValue)", pollAfter: false)
        }
    }

    // MARK: - Sleep timer

    func setSleepTimer(minutes: Int) {
        cancelSleepTimer()
        let until = Date().addingTimeInterval(TimeInterval(minutes * 60))
        sleepUntil = until
        let t = Timer(fire: until, interval: 0, repeats: false) { [weak self] _ in
            self?.sleepNow()
        }
        RunLoop.main.add(t, forMode: .common)
        sleepTimer = t
    }

    func setSleepAtTrackEnd() {
        cancelSleepTimer()
        sleepAtTrackEnd = true
        sleepTrackKey = track?.key
    }

    func cancelSleepTimer() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepUntil = nil
        sleepAtTrackEnd = false
        sleepTrackKey = nil
    }

    private func sleepNow() {
        cancelSleepTimer()
        guard track != nil else { return }
        let p = position
        isPlaying = false
        basePosition = p
        baseDate = Date()
        send("pause")
    }

    func toggleFavorite() {
        guard track?.source == .music, let term = favoriteTerm, let fav = isFavorite else { return }
        isFavorite = !fav
        send("set \(term) of current track to \(!fav)", pollAfter: false)
    }

    /// Baca status favorit lagu Apple Music. Coba "favorited" dulu, lalu "loved" untuk macOS lama.
    private func fetchFavorite() {
        guard let t = track, t.source == .music else {
            if isFavorite != nil { isFavorite = nil }
            return
        }
        let key = t.key
        let terms = favoriteTerm.map { [$0] } ?? ["favorited", "loved"]
        queue.async {
            var found: (term: String, value: Bool)?
            for term in terms {
                let r = Self.runOSA("tell application id \"com.apple.Music\" to get \(term) of current track")
                if r.error == nil, let out = r.output, out == "true" || out == "false" {
                    found = (term, out == "true")
                    break
                }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.track?.key == key else { return }
                if let found {
                    self.favoriteTerm = found.term
                    self.isFavorite = found.value
                } else {
                    self.isFavorite = nil
                }
            }
        }
    }

    private func send(_ command: String, pollAfter: Bool = true) {
        guard let source = track?.source else { return }
        let script = "tell application id \"\(source.bundleID)\" to \(command)"
        queue.async {
            _ = Self.runOSA(script)
            guard pollAfter else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.poll()
            }
        }
    }

    // MARK: - Polling

    func poll() {
        guard !isPolling else { return }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        // Hanya query app yang sedang jalan, supaya AppleScript tidak membuka app-nya.
        let active = MusicSource.allCases.filter { running.contains($0.bundleID) }
        if active.isEmpty {
            setError(nil)
            apply(nil)
            nextPollAt = Date().addingTimeInterval(Self.pollIntervalIdle)
            return
        }

        isPolling = true
        queue.async {
            let results = active.map { ($0, Self.runOSA($0 == .spotify ? Self.spotifyScript : Self.musicScript)) }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isPolling = false
                var snaps: [Snapshot] = []
                var errors: [String] = []
                for (source, result) in results {
                    switch self.parse(source, result) {
                    case .success(let snap?): snaps.append(snap)
                    case .success(nil): break
                    case .failure(let msg): errors.append(msg)
                    }
                }
                let chosen = self.choose(from: snaps)
                // Tampilkan error app yang gagal dibaca, juga saat app lain masih terbaca,
                // supaya kalau Music gagal kita tidak diam-diam menampilkan Spotify.
                self.setError(errors.first)
                if !errors.isEmpty { NSLog("NotchLyrics poll errors: %@", errors.joined(separator: " | ")) }
                self.apply(chosen)

                // Jadwalkan poll rutin berikutnya.
                let interval = self.isPlaying ? Self.pollIntervalPlaying : Self.pollIntervalIdle
                self.nextPollAt = Date().addingTimeInterval(interval)

                // Ada sinyal masuk selama poll berjalan → poll sekali lagi.
                if self.needsRepoll {
                    self.needsRepoll = false
                    self.poll()
                }
            }
        }
    }

    /// Kapan tiap app terakhir berubah dari diam ke memutar.
    private var playStartedAt: [MusicSource: Date] = [:]
    private var wasPlaying: [MusicSource: Bool] = [:]

    /// Saat satu app mulai memutar, pause app musik lain yang masih memutar.
    @Published var autoPauseOthers: Bool = (UserDefaults.standard.object(forKey: "autoPauseOthers") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(autoPauseOthers, forKey: "autoPauseOthers") }
    }

    /// Kirim perintah ke app tertentu (bukan ke app yang sedang ditampilkan).
    private func send(_ command: String, to source: MusicSource) {
        let script = "tell application id \"\(source.bundleID)\" to \(command)"
        queue.async {
            _ = Self.runOSA(script)
        }
    }

    /// Pilih app yang ditampilkan:
    /// 1. Kalau beberapa app memutar lagu, pilih yang PALING TERAKHIR mulai memutar.
    /// 2. Kalau tidak ada yang memutar, tetap di app yang sedang ditampilkan (kalau masih ada lagunya).
    /// 3. Selain itu, app pertama yang punya lagu.
    private func choose(from snaps: [Snapshot]) -> Snapshot? {
        let now = Date()
        var justStarted: [MusicSource] = []
        for s in snaps {
            let source = s.track.source
            if s.isPlaying && wasPlaying[source] != true {
                playStartedAt[source] = now
                justStarted.append(source)
            }
            wasPlaying[source] = s.isPlaying
        }

        // Tepat satu app baru mulai memutar → pause app lain yang masih jalan.
        // (Kalau lebih dari satu sekaligus, mis. saat NotchLyrics baru dibuka, jangan tebak-tebak.)
        if autoPauseOthers, justStarted.count == 1, let starter = justStarted.first {
            for s in snaps where s.isPlaying && s.track.source != starter {
                let other = s.track.source
                send("pause", to: other)
                wasPlaying[other] = false
            }
        }
        // App yang tidak terbaca lagi (ditutup / gagal) dianggap tidak memutar.
        let seen = Set(snaps.map { $0.track.source })
        for source in MusicSource.allCases where !seen.contains(source) {
            wasPlaying[source] = false
        }

        let playing = snaps.filter { $0.isPlaying }
        if let latest = playing.max(by: {
            (playStartedAt[$0.track.source] ?? .distantPast) < (playStartedAt[$1.track.source] ?? .distantPast)
        }) {
            return latest
        }
        if let current = track?.source, let same = snaps.first(where: { $0.track.source == current }) {
            return same
        }
        return snaps.first
    }

    private enum ParseResult {
        case success(Snapshot?)
        case failure(String)
    }

    private func parse(_ source: MusicSource, _ result: OSAResult) -> ParseResult {
        if let error = result.error {
            if result.errorCode == -1743 {
                if permissionDenied != source { permissionDenied = source }
            }
            return .failure("\(source.displayName): \(error)")
        }
        if permissionDenied == source { permissionDenied = nil }

        guard let out = result.output else {
            return .failure("\(source.displayName): hasil kosong")
        }
        if out == "stopped" { return .success(nil) } // tidak ada lagu, bukan error

        let p = out.components(separatedBy: "\u{1F}")
        guard p.count >= 8 else {
            return .failure("\(source.displayName): format tak dikenal: \(out.prefix(80))")
        }

        // Iklan Spotify: jangan cari lirik / tampilkan judulnya; anggap tidak ada lagu.
        if source == .spotify, p[1].hasPrefix("spotify:ad:") { return .success(nil) }

        let rawDuration = Self.number(p[5])
        let duration = source == .spotify ? rawDuration / 1000 : rawDuration // Spotify pakai milidetik
        let track = Track(source: source, id: p[1], title: p[2], artist: p[3], album: p[4], duration: duration)
        let volume: Double? = p.count > 8 && !p[8].isEmpty ? Self.number(p[8]) : nil

        // Shuffle & repeat (kosong kalau app tidak mendukung).
        let rawShuffle = p.count > 9 ? p[9] : ""
        let shuffle: Bool? = rawShuffle == "true" ? true : (rawShuffle == "false" ? false : nil)
        let rawRepeat = p.count > 10 ? p[10] : ""
        let repeatMode: RepeatMode?
        switch (source, rawRepeat) {
        case (.spotify, "true"): repeatMode = .all
        case (.spotify, "false"): repeatMode = .off
        case (.music, _): repeatMode = RepeatMode(rawValue: rawRepeat)
        default: repeatMode = nil
        }

        return .success(Snapshot(isPlaying: p[0] == "playing", track: track,
                                 position: Self.number(p[6]), artworkURL: p[7], volume: volume,
                                 shuffle: shuffle, repeatMode: repeatMode))
    }

    private func setError(_ message: String?) {
        if lastError != message {
            lastError = message
            if let message { NSLog("NotchLyrics: %@", message) }
        }
    }

    private func apply(_ snap: Snapshot?) {
        guard let snap else {
            if track != nil {
                track = nil
                artwork = nil
                artworkKey = nil
            }
            if isPlaying { isPlaying = false }
            if volume != nil { volume = nil }
            if isFavorite != nil { isFavorite = nil }
            if shuffle != nil { shuffle = nil }
            if repeatMode != nil { repeatMode = nil }
            return
        }

        let predicted = position
        let previousTrack = track
        let trackChanged = track != snap.track
        let stateChanged = isPlaying != snap.isPlaying

        if trackChanged { track = snap.track }
        if stateChanged { isPlaying = snap.isPlaying }

        // Koreksi posisi hanya kalau melenceng, supaya tidak "loncat-loncat".
        if trackChanged || stateChanged || !snap.isPlaying || abs(predicted - snap.position) > 0.5 {
            basePosition = snap.position
            baseDate = Date()
        }

        if artworkKey != snap.track.key {
            artworkKey = snap.track.key
            loadArtwork(for: snap)
        }

        if trackChanged { fetchFavorite() }

        // Jangan timpa volume yang baru saja diubah lewat slider.
        if Date() > volumeHoldUntil, volume != snap.volume {
            volume = snap.volume
        }
        // Sama untuk shuffle / repeat yang baru diklik.
        if Date() > modeHoldUntil {
            if shuffle != snap.shuffle { shuffle = snap.shuffle }
            if repeatMode != snap.repeatMode { repeatMode = snap.repeatMode }
        }

        // Sleep timer "sampai lagu ini selesai".
        if sleepAtTrackEnd, trackChanged, let prev = previousTrack {
            let endedNaturally = prev.duration <= 0 || predicted >= prev.duration - 4
            if endedNaturally, prev.key == sleepTrackKey {
                sleepNow()
            } else {
                // Lagu dilewati manual: timer pindah ke lagu yang sekarang.
                sleepTrackKey = snap.track.key
            }
        }
    }

    /// AppleScript memakai pemisah desimal sesuai locale (mis. "12,5" di locale Indonesia).
    private static func number(_ s: String) -> Double {
        Double(s.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    // MARK: - osascript

    /// Menjalankan AppleScript lewat /usr/bin/osascript (skrip dikirim lewat stdin).
    private static func runOSA(_ script: String) -> OSAResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-"]

        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return OSAResult(output: nil, error: "osascript gagal dijalankan: \(error.localizedDescription)", errorCode: nil)
        }

        stdin.fileHandleForWriting.write(Data(script.utf8))
        try? stdin.fileHandleForWriting.close()

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        var out = String(decoding: outData, as: UTF8.self)
        if out.hasSuffix("\n") { out.removeLast() }

        if process.terminationStatus != 0 {
            let err = String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return OSAResult(output: nil, error: err.isEmpty ? "error tidak diketahui" : err, errorCode: errorCode(in: err))
        }
        return OSAResult(output: out, error: nil, errorCode: nil)
    }

    /// Ambil kode error dari pesan seperti "... Not authorized to send Apple events to Music. (-1743)".
    private static func errorCode(in message: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: #"\((-?\d+)\)\s*$"#) else { return nil }
        let ns = message as NSString
        guard let m = regex.firstMatch(in: message, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return Int(ns.substring(with: m.range(at: 1)))
    }

    // MARK: - Artwork

    private func loadArtwork(for snap: Snapshot) {
        artwork = nil
        let key = snap.track.key
        let track = snap.track

        if !snap.artworkURL.isEmpty, let url = URL(string: snap.artworkURL) {
            fetchImage(url, key: key) { [weak self] in self?.searchArtwork(track) }
        } else {
            searchArtwork(track)
        }
    }

    private func fetchImage(_ url: URL, key: String, onFail: (() -> Void)? = nil) {
        URLSession.shared.dataTask(with: url) { data, _, _ in
            let image = data.flatMap { NSImage(data: $0) }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.artworkKey == key else { return }
                if let image {
                    self.artwork = image
                } else {
                    onFail?()
                }
            }
        }.resume()
    }

    /// Cover lewat iTunes Search API (dipakai untuk Apple Music dan sebagai cadangan Spotify).
    private func searchArtwork(_ track: Track) {
        guard var c = URLComponents(string: "https://itunes.apple.com/search") else { return }
        c.queryItems = [
            URLQueryItem(name: "term", value: "\(track.artist) \(track.title)"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "1"),
        ]
        guard let url = c.url else { return }
        let key = track.key
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]],
                  let art = results.first?["artworkUrl100"] as? String,
                  let artURL = URL(string: art.replacingOccurrences(of: "100x100", with: "300x300"))
            else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.artworkKey == key else { return }
                self.fetchImage(artURL, key: key)
            }
        }.resume()
    }

    // MARK: - AppleScript

    private static let spotifyScript = """
    set sep to character id 31
    tell application id "com.spotify.client"
        set curState to player state as text
        if curState is "stopped" then return curState
        set t to current track
        set shuf to ""
        set rep to ""
        try
            set shuf to (shuffling as text)
            set rep to (repeating as text)
        end try
        return curState & sep & (id of t) & sep & (name of t) & sep & (artist of t) & sep & (album of t) & sep & ((duration of t) as text) & sep & ((player position) as text) & sep & (artwork url of t) & sep & ((sound volume) as text) & sep & shuf & sep & rep
    end tell
    """

    private static let musicScript = """
    set sep to character id 31
    tell application id "com.apple.Music"
        set curState to player state as text
        if curState is "stopped" then return curState
        set t to current track
        set shuf to ""
        set rep to ""
        try
            set shuf to (shuffle enabled as text)
            set rep to (song repeat as text)
        end try
        return curState & sep & ((persistent ID of t) as text) & sep & (name of t) & sep & (artist of t) & sep & (album of t) & sep & ((duration of t) as text) & sep & ((player position) as text) & sep & "" & sep & ((sound volume) as text) & sep & shuf & sep & rep
    end tell
    """
}
