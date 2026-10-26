import AppKit
import Combine
import Security

/// Scrobble ke Last.fm. Login sekali lewat browser; kunci sesi disimpan di Keychain.
/// Butuh API key milik pengguna (gratis): https://www.last.fm/api/account/create
final class LastFMModule: ObservableObject {
    @Published var apiKey: String = UserDefaults.standard.string(forKey: "lastfm.key") ?? "" {
        didSet { UserDefaults.standard.set(apiKey.trimmingCharacters(in: .whitespaces), forKey: "lastfm.key") }
    }
    @Published var apiSecret: String = UserDefaults.standard.string(forKey: "lastfm.secret") ?? "" {
        didSet { UserDefaults.standard.set(apiSecret.trimmingCharacters(in: .whitespaces), forKey: "lastfm.secret") }
    }
    /// Spotify sudah bisa scrobble sendiri, jadi default hanya Apple Music.
    @Published var onlyAppleMusic: Bool = Defaults.bool("lastfm.onlyMusic", true) {
        didSet { UserDefaults.standard.set(onlyAppleMusic, forKey: "lastfm.onlyMusic") }
    }
    @Published private(set) var username: String? = UserDefaults.standard.string(forKey: "lastfm.user")
    @Published private(set) var status = ""
    @Published private(set) var awaitingApproval = false

    var isConnected: Bool { sessionKey != nil && username != nil }

    private var pendingToken: String?
    private var cancellables = Set<AnyCancellable>()

    // Pelacakan lagu yang sedang diputar.
    private var current: Track?
    private var startedAt = Date()
    private var played: TimeInterval = 0
    private var resumedAt: Date?

    // MARK: - Login

    func beginAuth() {
        guard !apiKey.isEmpty, !apiSecret.isEmpty else {
            status = L("Isi API key & secret dulu.", "Fill in the API key & secret first.")
            return
        }
        status = L("Menghubungkan…", "Connecting…")
        call("auth.getToken", [:]) { [weak self] json in
            guard let self else { return }
            guard let token = json?["token"] as? String,
                  let url = URL(string: "https://www.last.fm/api/auth/?api_key=\(self.apiKey)&token=\(token)") else {
                self.status = self.errorText(json)
                return
            }
            self.pendingToken = token
            self.awaitingApproval = true
            self.status = L("Setujui akses di browser, lalu klik Selesai.", "Approve access in your browser, then click Done.")
            NSWorkspace.shared.open(url)
        }
    }

    func finishAuth() {
        guard let token = pendingToken else { return }
        call("auth.getSession", ["token": token]) { [weak self] json in
            guard let self else { return }
            guard let session = json?["session"] as? [String: Any],
                  let key = session["key"] as? String,
                  let name = session["name"] as? String else {
                self.status = self.errorText(json)
                return
            }
            Keychain.set(key, account: "lastfm.session")
            UserDefaults.standard.set(name, forKey: "lastfm.user")
            self.username = name
            self.pendingToken = nil
            self.awaitingApproval = false
            self.status = L("Tersambung sebagai \(name).", "Connected as \(name).")
        }
    }

    func disconnect() {
        Keychain.delete(account: "lastfm.session")
        UserDefaults.standard.removeObject(forKey: "lastfm.user")
        username = nil
        status = ""
    }

    private var sessionKey: String? { Keychain.get(account: "lastfm.session") }

    // MARK: - Scrobble

    func bind(to player: PlayerMonitor) {
        player.$track
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak player] track in
                self?.trackChanged(to: track, playing: player?.isPlaying ?? false)
            }
            .store(in: &cancellables)
        player.$isPlaying
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] playing in self?.playingChanged(playing) }
            .store(in: &cancellables)
    }

    private func playingChanged(_ playing: Bool) {
        if playing {
            if resumedAt == nil { resumedAt = Date() }
        } else if let since = resumedAt {
            played += Date().timeIntervalSince(since)
            resumedAt = nil
        }
    }

    private func trackChanged(to track: Track?, playing: Bool) {
        // Tutup lagu sebelumnya.
        if let previous = current {
            if let since = resumedAt { played += Date().timeIntervalSince(since) }
            if LastFMCore.shouldScrobble(duration: previous.duration, played: played) {
                scrobble(previous, startedAt: startedAt)
            }
        }
        current = track
        startedAt = Date()
        played = 0
        resumedAt = playing ? Date() : nil
        if let track, playing { nowPlaying(track) }
    }

    private func eligible(_ track: Track) -> Bool {
        isConnected && (!onlyAppleMusic || track.source == .music)
    }

    private func nowPlaying(_ track: Track) {
        guard eligible(track), let sk = sessionKey else { return }
        var p = ["artist": track.artist, "track": track.title, "sk": sk]
        if !track.album.isEmpty { p["album"] = track.album }
        if track.duration > 0 { p["duration"] = String(Int(track.duration)) }
        call("track.updateNowPlaying", p) { _ in }
    }

    private func scrobble(_ track: Track, startedAt: Date) {
        guard eligible(track), let sk = sessionKey else { return }
        var p = ["artist": track.artist, "track": track.title, "sk": sk,
                 "timestamp": String(Int(startedAt.timeIntervalSince1970))]
        if !track.album.isEmpty { p["album"] = track.album }
        if track.duration > 0 { p["duration"] = String(Int(track.duration)) }
        call("track.scrobble", p) { [weak self] json in
            if json?["error"] != nil { self?.status = self?.errorText(json) ?? "" }
        }
    }

    // MARK: - API

    private func call(_ method: String, _ params: [String: String], completion: @escaping ([String: Any]?) -> Void) {
        var p = params
        p["method"] = method
        p["api_key"] = apiKey
        p["api_sig"] = LastFMCore.signature(p, secret: apiSecret)
        p["format"] = "json"
        guard let url = URL(string: "https://ws.audioscrobbler.com/2.0/") else { return completion(nil) }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = LastFMCore.formBody(p)
        URLSession.shared.dataTask(with: request) { data, _, _ in
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            DispatchQueue.main.async { completion(json) }
        }.resume()
    }

    private func errorText(_ json: [String: Any]?) -> String {
        if let message = json?["message"] as? String { return "Last.fm: \(message)" }
        return L("Last.fm tidak bisa dihubungi.", "Couldn't reach Last.fm.")
    }
}

/// Penyimpanan kecil di Keychain (password generik).
enum Keychain {
    private static let service = "com.rezaprahenda.popocu"

    static func set(_ value: String, account: String) {
        delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func get(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
