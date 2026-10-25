import Foundation

/// Menyimpan lirik dan terjemahan ke disk supaya lagu yang pernah diputar langsung tampil
/// (juga saat offline) setelah app dibuka ulang.
/// Lokasi: ~/Library/Application Support/NotchLyrics/cache.json
final class DiskCache {
    private struct Store: Codable {
        var lyrics: [String: LyricsState] = [:]
        var translations: [String: [Int: String]] = [:]
        /// Kapan entri terakhir dipakai, untuk membuang yang paling lama kalau cache terlalu besar.
        var touched: [String: Date] = [:]
    }

    /// Batas jumlah lagu yang disimpan.
    private static let maxEntries = 1500

    private var store = Store()
    private let fileURL: URL?
    private let ioQueue = DispatchQueue(label: "notchlyrics.diskcache", qos: .utility)
    private var saveWork: DispatchWorkItem?

    init() {
        let fm = FileManager.default
        if let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let dir = base.appendingPathComponent("NotchLyrics", isDirectory: true)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            fileURL = dir.appendingPathComponent("cache.json")
        } else {
            fileURL = nil
        }
        load()
    }

    var lyrics: [String: LyricsState] { store.lyrics }
    var translations: [String: [Int: String]] { store.translations }

    func setLyrics(_ state: LyricsState?, for key: String) {
        // Hanya hasil yang berguna yang disimpan; "loading" / "notFound" tidak.
        switch state {
        case .synced?, .plain?, .instrumental?:
            store.lyrics[key] = state
        default:
            store.lyrics[key] = nil
            store.translations[key] = nil
        }
        touch(key)
    }

    func setTranslation(_ map: [Int: String]?, for key: String) {
        store.translations[key] = map
        touch(key)
    }

    // MARK: - Internal

    private func touch(_ key: String) {
        if store.lyrics[key] == nil && store.translations[key] == nil {
            store.touched[key] = nil
        } else {
            store.touched[key] = Date()
        }
        prune()
        scheduleSave()
    }

    private func prune() {
        guard store.touched.count > Self.maxEntries else { return }
        let oldest = store.touched
            .sorted { $0.value < $1.value }
            .prefix(store.touched.count - Self.maxEntries)
        for (key, _) in oldest {
            store.lyrics[key] = nil
            store.translations[key] = nil
            store.touched[key] = nil
        }
    }

    private func load() {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(Store.self, from: data)
        else { return }
        store = decoded
    }

    /// Tulis ke disk dengan jeda 2 detik, supaya beberapa perubahan beruntun cukup ditulis sekali.
    private func scheduleSave() {
        guard let url = fileURL else { return }
        saveWork?.cancel()
        let snapshot = store
        let work = DispatchWorkItem { [ioQueue] in
            ioQueue.async {
                guard let data = try? JSONEncoder().encode(snapshot) else { return }
                try? data.write(to: url, options: .atomic)
            }
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }
}
