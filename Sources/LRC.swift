import Foundation

/// Satu baris lirik tersinkron.
struct LyricLine: Identifiable, Equatable, Codable {
    let id: Int
    let time: Double
    let text: String
}

/// Logika lirik murni (tanpa UI / jaringan), supaya bisa dites otomatis.
enum LRC {
    /// Parse format LRC: "[01:23.45] teks". Satu baris bisa punya beberapa timestamp.
    /// Hasil diurutkan menurut waktu; `id` = urutan setelah diurutkan.
    static func parse(_ s: String) -> [LyricLine] {
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
            .enumerated()
            .sorted { $0.element.0 != $1.element.0 ? $0.element.0 < $1.element.0 : $0.offset < $1.offset }
            .enumerated()
            .map { LyricLine(id: $0.offset, time: $0.element.element.0, text: $0.element.element.1) }
    }

    /// Indeks baris terakhir yang waktunya <= `time` (binary search).
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

    /// Seberapa jauh baris `index` sudah dinyanyikan pada waktu `time` (0…1), untuk karaoke.
    /// Selesai 0,3 detik sebelum baris berikutnya supaya terasa "habis" tepat waktu.
    static func progress(in lines: [LyricLine], index: Int, at time: Double) -> Double {
        guard lines.indices.contains(index) else { return 0 }
        let start = lines[index].time
        let end = index + 1 < lines.count ? lines[index + 1].time : start + 5
        let length = max(end - start - 0.3, 0.3)
        return min(max((time - start) / length, 0), 1)
    }

    /// Judul untuk pencarian: buang "- Remastered", "(feat. ...)", "[with ...]", dst.
    static func cleanTitle(_ title: String) -> String {
        var t = title
        if let r = t.range(of: " - ") { t = String(t[..<r.lowerBound]) }
        t = t.replacingOccurrences(
            of: #"\s*[\(\[](feat\.|ft\.|with |from |remaster)[^\)\]]*[\)\]]"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        return t.trimmingCharacters(in: .whitespaces)
    }

    /// Artis pertama dari "A, B & C".
    static func primaryArtist(_ a: String) -> String {
        a.components(separatedBy: CharacterSet(charactersIn: ",&"))
            .first?
            .trimmingCharacters(in: .whitespaces) ?? a
    }
}
