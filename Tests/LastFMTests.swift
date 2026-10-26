import Foundation

func lastFMTests() {
    suite("LastFMCore") {
        expectEqual(LastFMCore.signature(["api_key": "abc", "method": "auth.getSession", "token": "123"], secret: "SECRET"),
                    "08b10cee11b1f0c2a511311452f5f4e5", "tanda tangan diurutkan menurut nama parameter")
        expectEqual(LastFMCore.signature(["track": "La Vie en rose", "artist": "Édith Piaf", "method": "track.scrobble",
                                          "timestamp": "1700000000", "format": "json"], secret: "S"),
                    "891933118108af0541fd2f8cd4f7c570", "UTF-8, dan 'format' tidak ikut ditandatangani")

        expect(!LastFMCore.shouldScrobble(duration: 25, played: 25), "lagu ≤ 30 detik tidak di-scrobble")
        expect(!LastFMCore.shouldScrobble(duration: 200, played: 90), "kurang dari separuh")
        expect(LastFMCore.shouldScrobble(duration: 200, played: 100), "tepat separuh")
        expect(LastFMCore.shouldScrobble(duration: 1200, played: 240), "lagu panjang: cukup 4 menit")
        expect(!LastFMCore.shouldScrobble(duration: 1200, played: 239), "lagu panjang: kurang dari 4 menit")

        let body = String(decoding: LastFMCore.formBody(["track": "A & B", "artist": "Ç"]), as: UTF8.self)
        expectEqual(body, "artist=%C3%87&track=A%20%26%20B", "form body di-encode")
    }
}
