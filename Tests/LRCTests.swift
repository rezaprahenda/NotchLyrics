import Foundation

func lrcTests() {
    suite("LRC.parse") {
        let lines = LRC.parse("""
        [ar: Artis]
        [00:12.50] Baris dua
        [00:01.00]Baris satu
        [01:02:30] Format titik dua
        [00:20.00][00:40.00] Diulang
        teks tanpa waktu
        [00:50.00]
        """)
        expectEqual(lines.count, 6, "jumlah baris (metadata & teks tanpa waktu dibuang)")
        expectEqual(lines.map(\.text), ["Baris satu", "Baris dua", "Diulang", "Diulang", "", "Format titik dua"],
                    "urutan menurut waktu")
        expect(near(lines[0].time, 1.0), "waktu 00:01.00")
        expect(near(lines[1].time, 12.5), "waktu 00:12.50")
        expect(near(lines[5].time, 62.3), "format [01:02:30] = 62,3 detik")
        expectEqual(lines.map(\.id), Array(0..<6), "id = urutan")
        expect(LRC.parse("").isEmpty, "string kosong")
    }

    suite("LRC.index") {
        let lines = LRC.parse("[00:10.00]a\n[00:20.00]b\n[00:30.00]c")
        expectEqual(LRC.index(in: lines, at: 5), nil, "sebelum baris pertama")
        expectEqual(LRC.index(in: lines, at: 10), 0, "tepat di baris pertama")
        expectEqual(LRC.index(in: lines, at: 25), 1, "di tengah")
        expectEqual(LRC.index(in: lines, at: 999), 2, "setelah baris terakhir")
        expectEqual(LRC.index(in: [], at: 5), nil, "tanpa baris")
    }

    suite("LRC.progress (karaoke)") {
        let lines = LRC.parse("[00:10.00]a\n[00:20.30]b")
        expect(near(LRC.progress(in: lines, index: 0, at: 5), 0), "sebelum mulai = 0")
        expect(near(LRC.progress(in: lines, index: 0, at: 15), 0.5), "pertengahan = 0,5")
        expect(near(LRC.progress(in: lines, index: 0, at: 20.1), 1), "sudah habis 0,3 dtk sebelum baris berikut")
        expect(near(LRC.progress(in: lines, index: 1, at: 22.65), 0.5), "baris terakhir dianggap 5 detik")
        expect(near(LRC.progress(in: lines, index: 9, at: 15), 0), "indeks tidak valid = 0")
    }

    suite("LRC.cleanTitle & primaryArtist") {
        expectEqual(LRC.cleanTitle("Song - Remastered 2011"), "Song", "buang '- Remastered'")
        expectEqual(LRC.cleanTitle("Song (feat. Someone)"), "Song", "buang (feat.)")
        expectEqual(LRC.cleanTitle("Song [with Band]"), "Song", "buang [with]")
        expectEqual(LRC.cleanTitle("Song (Live)"), "Song (Live)", "kurung lain dipertahankan")
        expectEqual(LRC.primaryArtist("A, B & C"), "A", "artis pertama")
        expectEqual(LRC.primaryArtist("Solo"), "Solo", "satu artis")
    }
}
