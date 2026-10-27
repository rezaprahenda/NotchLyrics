import Foundation

// Bagian murni integrasi notecu (dites di Tests/). Bentuk data mengikuti server notecu:
// satu "item" = catatan / folder / tugas, disinkron lewat POST /api/sync {after, items}.

/// Nilai JSON apa saja, supaya kolom yang tidak dikenal popocu tetap utuh saat dikirim balik.
enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n):
            if n.rounded() == n, abs(n) < 1e15 { try c.encode(Int64(n)) } else { try c.encode(n) }
        case .bool(let b): try c.encode(b)
        case .object(let o): try c.encode(o)
        case .array(let a): try c.encode(a)
        case .null: try c.encodeNil()
        }
    }

    var string: String? { if case .string(let s) = self { return s }; return nil }
    var number: Double? { if case .number(let n) = self { return n }; return nil }
    var bool: Bool? { if case .bool(let b) = self { return b }; return nil }
}

/// Satu item notecu. Semua kolom disimpan apa adanya; popocu hanya membaca yang ia butuhkan.
struct NotecuItem: Codable, Equatable, Identifiable {
    var fields: [String: JSONValue]

    init(fields: [String: JSONValue]) { self.fields = fields }
    init(from decoder: Decoder) throws { fields = try [String: JSONValue](from: decoder) }
    func encode(to encoder: Encoder) throws { try fields.encode(to: encoder) }

    var id: String { fields["id"]?.string ?? "" }
    var kind: String { fields["kind"]?.string ?? "" }
    var updatedAt: Double {
        get { fields["updatedAt"]?.number ?? 0 }
        set { fields["updatedAt"] = .number(newValue) }
    }
    var rev: Int? {
        get { fields["rev"]?.number.map { Int($0) } }
        set { fields["rev"] = newValue.map { .number(Double($0)) } ?? .null }
    }
    var isDeleted: Bool { fields["deleted"]?.bool ?? false }
    var isTrashed: Bool { fields["trashedAt"]?.number != nil }
    var isLive: Bool { !isDeleted && !isTrashed }
    var isPinned: Bool { fields["pinned"]?.bool ?? false }
    var isImportant: Bool { fields["important"]?.bool ?? false }
    var text: String { fields["text"]?.string ?? "" }
    var due: String? { fields["due"]?.string }
    var dueTime: String? { fields["dueTime"]?.string }
    var isDone: Bool { fields["doneAt"]?.number != nil }

    /// Judul: kolom title, atau (catatan lama) baris pertama yang berisi.
    var displayTitle: String {
        let raw: String
        if let t = fields["title"]?.string { raw = t } else { raw = NotecuCore.splitLegacy(text).title }
        let t = raw.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? L("Tanpa judul", "Untitled") : t
    }

    /// Isi tanpa judul, dipotong untuk pratinjau.
    var snippet: String {
        let body = fields["title"]?.string != nil ? text : NotecuCore.splitLegacy(text).body
        return body.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
    }
}

enum NotecuCore {
    /// ID baru dengan skema yang sama seperti app notecu: awalan + waktu (basis 36) + acak.
    static func newID(_ prefix: String, now: Date = Date()) -> String {
        let t = String(Int(now.timeIntervalSince1970 * 1000), radix: 36)
        let r = String(UInt32.random(in: 0...UInt32.max), radix: 36)
        return prefix + t + r
    }

    static func millis(_ date: Date = Date()) -> Double { (date.timeIntervalSince1970 * 1000).rounded() }

    /// Catatan lama: baris pertama yang berisi jadi judul ("# " dibuang), sisanya isi.
    static func splitLegacy(_ text: String) -> (title: String, body: String) {
        var lines = text.components(separatedBy: "\n")
        guard let i = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return ("", "") }
        var title = lines[i].trimmingCharacters(in: .whitespaces)
        while title.hasPrefix("#") { title.removeFirst() }
        lines.removeSubrange(0...i)
        while let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeFirst() }
        return (title.trimmingCharacters(in: .whitespaces), lines.joined(separator: "\n"))
    }

    /// Catatan baru dari teks yang diketik: baris pertama = judul, sisanya isi.
    static func makeNote(from input: String, now: Date = Date()) -> NotecuItem? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var lines = trimmed.components(separatedBy: "\n")
        let title = lines.removeFirst().trimmingCharacters(in: .whitespaces)
        let ms = millis(now)
        return NotecuItem(fields: [
            "id": .string(newID("n", now: now)), "kind": .string("note"),
            "title": .string(title), "text": .string(lines.joined(separator: "\n")),
            "pinned": .bool(false), "createdAt": .number(ms), "updatedAt": .number(ms),
        ])
    }

    /// Tugas baru bertenggat hari ini.
    static func makeTask(title: String, due: String?, now: Date = Date()) -> NotecuItem? {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        let ms = millis(now)
        var f: [String: JSONValue] = [
            "id": .string(newID("t", now: now)), "kind": .string("task"),
            "title": .string(t), "text": .string(""), "createdAt": .number(ms), "updatedAt": .number(ms),
        ]
        if let due { f["due"] = .string(due) }
        return NotecuItem(fields: f)
    }

    /// Tugas yang perlu dikerjakan: belum selesai, tenggat hari ini atau sudah lewat.
    /// Urutan: terlambat dulu, lalu yang penting, lalu jam tenggat.
    static func tasksDue(_ items: [NotecuItem], today: String) -> [NotecuItem] {
        items.filter { $0.kind == "task" && $0.isLive && !$0.isDone && ($0.due.map { $0 <= today } ?? false) }
            .sorted { a, b in
                let ao = a.due! < today, bo = b.due! < today
                if ao != bo { return ao }
                if a.isImportant != b.isImportant { return a.isImportant }
                let at = a.dueTime ?? "99:99", bt = b.dueTime ?? "99:99"
                if at != bt { return at < bt }
                return a.displayTitle < b.displayTitle
            }
    }

    /// Catatan terbaru: disematkan dulu, lalu yang terakhir diubah.
    static func recentNotes(_ items: [NotecuItem], limit: Int) -> [NotecuItem] {
        Array(items.filter { $0.kind == "note" && $0.isLive }
            .sorted { a, b in
                if a.isPinned != b.isPinned { return a.isPinned }
                return a.updatedAt > b.updatedAt
            }
            .prefix(limit))
    }

    /// Gabungkan perubahan dari server; item yang masih menunggu dikirim (dirty) tidak ditimpa.
    static func merge(_ current: [String: NotecuItem], incoming: [NotecuItem], dirty: Set<String>) -> [String: NotecuItem] {
        var next = current
        for item in incoming where !item.id.isEmpty && !dirty.contains(item.id) {
            next[item.id] = item
        }
        return next
    }

    /// "yyyy-MM-dd" waktu lokal (format tenggat notecu).
    static func dayString(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
