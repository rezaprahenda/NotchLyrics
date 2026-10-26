import Foundation
import CryptoKit

// Bagian Last.fm yang murni (dites di Tests/): tanda tangan API dan aturan scrobble.

enum LastFMCore {
    /// api_sig = md5(semua parameter diurutkan menurut nama, "namanilai" digabung, + secret).
    /// Parameter "format" dan "callback" tidak ikut ditandatangani.
    static func signature(_ params: [String: String], secret: String) -> String {
        let base = params.keys
            .filter { $0 != "format" && $0 != "callback" }
            .sorted()
            .map { $0 + (params[$0] ?? "") }
            .joined() + secret
        return Insecure.MD5.hash(data: Data(base.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Aturan Last.fm: lagu > 30 detik, diputar setidaknya separuhnya atau 4 menit.
    static func shouldScrobble(duration: Double, played: Double) -> Bool {
        guard duration > 30 else { return false }
        return played >= min(duration / 2, 240)
    }

    /// Body POST application/x-www-form-urlencoded.
    static func formBody(_ params: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let body = params.keys.sorted().map { key in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = (params[key] ?? "").addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
            return "\(k)=\(v)"
        }.joined(separator: "&")
        return Data(body.utf8)
    }
}
