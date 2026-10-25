import Foundation

/// Mengubah lirik berhuruf non-latin ke huruf latin, sepenuhnya offline memakai fitur bawaan macOS.
/// - Jepang (ada hiragana/katakana): romaji lewat CFStringTokenizer, yang tahu cara baca kanji.
/// - Lainnya (Korea, Mandarin, Rusia, Thai, ...): transformasi "Any-Latin" ICU.
enum Romanizer {
    /// Ada huruf di luar Latin (dasar, Latin-1, Extended-A/B, Extended Additional)?
    static func isNonLatin(_ s: String) -> Bool {
        s.unicodeScalars.contains { sc in
            sc.properties.isAlphabetic
                && sc.value > 0x024F
                && !(0x1E00...0x1EFF).contains(sc.value)
        }
    }

    static func containsKana(_ s: String) -> Bool {
        s.unicodeScalars.contains {
            (0x3040...0x30FF).contains($0.value) || (0x31F0...0x31FF).contains($0.value)
        }
    }

    /// `lines`: (id, teks). Hasil: id → teks latin, hanya untuk baris yang memang non-latin.
    static func romanize(_ lines: [(Int, String)]) -> [Int: String] {
        // Tentukan per lagu: kalau ada kana di salah satu baris, perlakukan semuanya sebagai bahasa Jepang
        // (supaya baris yang isinya kanji saja tidak terbaca sebagai pinyin).
        let japanese = lines.contains { containsKana($0.1) }
        var out: [Int: String] = [:]
        for (id, text) in lines where isNonLatin(text) {
            let latin = japanese
                ? japaneseToRomaji(text)
                : (text.applyingTransform(.toLatin, reverse: false) ?? text)
            let cleaned = tidy(latin)
            if !cleaned.isEmpty, cleaned != text {
                out[id] = cleaned
            }
        }
        return out
    }

    /// Partikel yang ditulis は/へ/を tapi dibaca wa/e/o.
    private static let particles: [String: String] = ["は": "wa", "へ": "e", "を": "o"]

    static func japaneseToRomaji(_ text: String) -> String {
        let ns = text as NSString
        let cf = text as CFString
        let length = CFStringGetLength(cf)
        guard let tokenizer = CFStringTokenizerCreate(kCFAllocatorDefault,
                                                      cf,
                                                      CFRangeMake(0, length),
                                                      kCFStringTokenizerUnitWord,
                                                      Locale(identifier: "ja") as CFLocale)
        else { return text }

        var pieces: [String] = []
        var cursor = 0
        var type = CFStringTokenizerAdvanceToNextToken(tokenizer)
        while type.rawValue != 0 {
            let r = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            // Teks di antara kata (spasi, tanda baca) ikut disalin apa adanya.
            if r.location > cursor {
                pieces.append(ns.substring(with: NSRange(location: cursor, length: r.location - cursor)))
            }
            let token = ns.substring(with: NSRange(location: r.location, length: r.length))
            if let particle = particles[token] {
                pieces.append(particle)
            } else if let latin = CFStringTokenizerCopyCurrentTokenAttribute(
                tokenizer, kCFStringTokenizerAttributeLatinTranscription
            ) as? String, !latin.isEmpty {
                pieces.append(latin)
            } else {
                pieces.append(token.applyingTransform(.toLatin, reverse: false) ?? token)
            }
            cursor = r.location + r.length
            type = CFStringTokenizerAdvanceToNextToken(tokenizer)
        }
        if cursor < length {
            pieces.append(ns.substring(from: cursor))
        }
        return pieces.joined(separator: " ")
    }

    /// Rapikan tanda baca Jepang/full-width dan spasi berlebih.
    static func tidy(_ s: String) -> String {
        var t = s
        let map: [String: String] = [
            "、": ",", "。": ".", "「": "\"", "」": "\"", "『": "\"", "』": "\"",
            "！": "!", "？": "?", "　": " ", "～": "~", "・": " ", "（": "(", "）": ")",
        ]
        for (k, v) in map { t = t.replacingOccurrences(of: k, with: v) }
        t = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s+([,.!?…)\]~])"#, with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: #"([(\[])\s+"#, with: "$1", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespaces)
    }
}
