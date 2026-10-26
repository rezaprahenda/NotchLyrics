import Foundation

/// Pindahan sekali jalan dari NotchLyrics ke popocu: pengaturan, offset, pilihan lirik manual,
/// dan cache lirik/terjemahan ikut dibawa. Izin Automation (Spotify/Music) dan "buka saat login"
/// melekat ke identitas app lama, jadi macOS akan memintanya ulang.
enum Migration {
    static let oldBundleID = "local.notchlyrics.app"
    private static let doneKey = "migratedFromNotchLyrics"

    /// Dipanggil paling awal, sebelum objek apa pun membaca UserDefaults.
    static func runIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }

        if let old = defaults.persistentDomain(forName: oldBundleID) {
            for (key, value) in old where defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
            NSLog("popocu: %d pengaturan dipindahkan dari NotchLyrics", old.count)
        }

        let fm = FileManager.default
        if let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let oldFile = base.appendingPathComponent("NotchLyrics/cache.json")
            let newDir = base.appendingPathComponent("popocu", isDirectory: true)
            let newFile = newDir.appendingPathComponent("cache.json")
            if fm.fileExists(atPath: oldFile.path), !fm.fileExists(atPath: newFile.path) {
                try? fm.createDirectory(at: newDir, withIntermediateDirectories: true)
                try? fm.copyItem(at: oldFile, to: newFile)
            }
        }

        defaults.set(true, forKey: doneKey)
    }
}
