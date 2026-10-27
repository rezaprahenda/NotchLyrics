import Foundation

func notecuTests() {
    suite("NotecuCore") {
        // Kolom tak dikenal tetap utuh saat di-decode lalu di-encode ulang.
        let json = #"{"id":"n1","kind":"note","updatedAt":1700000000000,"title":"Belanja","text":"- [ ] susu","color":"teal","future":{"x":[1,true,null]},"rev":12}"#
        let item = try! JSONDecoder().decode(NotecuItem.self, from: Data(json.utf8))
        expectEqual(item.id, "n1", "id")
        expectEqual(item.rev, 12, "rev")
        expectEqual(item.displayTitle, "Belanja", "judul dari kolom title")
        expectEqual(item.snippet, "- [ ] susu", "pratinjau isi")
        let again = try! JSONDecoder().decode(NotecuItem.self, from: try! JSONEncoder().encode(item))
        expectEqual(again, item, "round-trip tanpa kehilangan kolom")
        let raw = String(decoding: try! JSONEncoder().encode(item), as: UTF8.self)
        expect(raw.contains("1700000000000") && !raw.contains("e+"), "milidetik tetap bilangan bulat")

        let legacy = NotecuItem(fields: ["id": .string("n2"), "kind": .string("note"), "text": .string("\n# Ide app\n\nisi pertama\nisi kedua")])
        expectEqual(legacy.displayTitle, "Ide app", "catatan lama: judul dari baris pertama")
        expectEqual(legacy.snippet, "isi pertama", "catatan lama: pratinjau setelah judul")

        let note = NotecuCore.makeNote(from: "  Rapat besok\nbawa laptop\n")!
        expectEqual(note.kind, "note", "jenis catatan")
        expectEqual(note.fields["title"]?.string, "Rapat besok", "baris pertama jadi judul")
        expectEqual(note.text, "bawa laptop", "sisanya isi")
        expect(note.id.hasPrefix("n"), "id catatan berawalan n")
        expect(NotecuCore.makeNote(from: "  \n ") == nil, "teks kosong tidak jadi catatan")

        func task(_ id: String, _ due: String?, important: Bool = false, time: String? = nil, done: Bool = false, trashed: Bool = false) -> NotecuItem {
            var f: [String: JSONValue] = ["id": .string(id), "kind": .string("task"), "title": .string(id), "updatedAt": .number(1)]
            if let due { f["due"] = .string(due) }
            if important { f["important"] = .bool(true) }
            if let time { f["dueTime"] = .string(time) }
            if done { f["doneAt"] = .number(5) }
            if trashed { f["trashedAt"] = .number(5) }
            return NotecuItem(fields: f)
        }
        let tasks = [task("besok", "2026-10-28"), task("hariIni", "2026-10-27", time: "15:00"),
                     task("penting", "2026-10-27", important: true), task("telat", "2026-10-25"),
                     task("selesai", "2026-10-27", done: true), task("tanpaTanggal", nil),
                     task("sampah", "2026-10-27", trashed: true), task("pagi", "2026-10-27", time: "08:00")]
        expectEqual(NotecuCore.tasksDue(tasks, today: "2026-10-27").map(\.id), ["telat", "penting", "pagi", "hariIni"],
                    "terlambat, penting, lalu jam; tanpa yang selesai/sampah/besok")

        func note(_ id: String, _ updated: Double, pinned: Bool = false) -> NotecuItem {
            NotecuItem(fields: ["id": .string(id), "kind": .string("note"), "updatedAt": .number(updated), "pinned": .bool(pinned)])
        }
        let notes = [note("lama", 1), note("baru", 3), note("sematan", 2, pinned: true),
                     NotecuItem(fields: ["id": .string("hapus"), "kind": .string("note"), "updatedAt": .number(9), "deleted": .bool(true)])]
        expectEqual(NotecuCore.recentNotes(notes, limit: 2).map(\.id), ["sematan", "baru"], "disematkan dulu, lalu terbaru")

        let current = ["a": note("a", 1), "b": note("b", 1)]
        let merged = NotecuCore.merge(current, incoming: [note("a", 5), note("b", 5), note("c", 5)], dirty: ["b"])
        expectEqual(merged["a"]?.updatedAt, 5, "perubahan server diterima")
        expectEqual(merged["b"]?.updatedAt, 1, "editan lokal yang belum terkirim tidak ditimpa")
        expect(merged["c"] != nil, "item baru dari server ditambahkan")

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        expectEqual(NotecuCore.dayString(Date(timeIntervalSince1970: 1_793_035_800), calendar: cal), "2026-10-27", "tanggal lokal")
    }
}
