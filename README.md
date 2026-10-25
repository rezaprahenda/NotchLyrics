# NotchLyrics

Aplikasi kecil macOS yang mengubah notch MacBook jadi "Dynamic Island" untuk musik:
lirik tersinkron dari Spotify / Apple Music, cover album, dan kontrol play/pause/next.

## Kebutuhan

- macOS 14 (Sonoma) atau lebih baru
- Command Line Tools: `xcode-select --install` (Xcode penuh juga boleh)
- Spotify desktop dan/atau Apple Music

## Build & jalankan

```bash
cd NotchLyrics
chmod +x build.sh
./build.sh run
```

Hasilnya ada di `build/NotchLyrics.app`. Untuk memasang ke Applications sekaligus menjalankannya:

```bash
./build.sh install
```

## Pertama kali dijalankan

macOS akan bertanya **"NotchLyrics wants to control Spotify/Music"** → klik **OK**.
Kalau terlanjur klik "Don't Allow", aktifkan lagi di
System Settings › Privacy & Security › Automation › NotchLyrics.

Catatan: karena app ditandatangani ad-hoc, izin ini kadang diminta ulang setiap kali di-build ulang.

## Cara pakai

- **Mode ringkas** (otomatis saat ada lagu): cover di kiri notch, equalizer di kanan,
  dan satu baris lirik yang sedang dinyanyikan di bawah notch.
- **Mode lebar** (arahkan kursor ke notch): judul, artis, kontrol musik, lirik berjalan, progress bar.
- **Klik baris lirik** di mode lebar untuk lompat ke bagian lagu itu.
- **Tombol − / + di pojok kanan atas lirik** untuk menggeser waktu lirik 0,5 detik
  (+ = lirik lebih cepat). Disimpan per lagu. Klik angkanya untuk reset.
- **Progress bar**: klik atau drag untuk lompat ke bagian lagu.
- **Slider volume** di sebelah progress bar (volume Spotify/Music, bukan volume sistem).
- **Tombol ♡** untuk menandai lagu favorit (khusus Apple Music).
- **Tombol "ID"** untuk menampilkan terjemahan bahasa Indonesia di bawah tiap baris lirik
  (macOS 15+, memakai fitur terjemahan bawaan macOS; unduh bahasa Indonesia di
  System Settings › General › Language & Region › Translation Languages kalau diminta).
- **Tombol "Aa"** (muncul untuk lirik berhuruf non-latin seperti Jepang/Korea/Mandarin):
  tampilkan baris latin (romaji, romanisasi Hangul, pinyin), offline.
- **Tombol 🔍 di pojok lirik** (atau "Cari lirik lain" saat lirik tidak ketemu): pilih lirik lain dari
  LRCLIB. Durasi hijau = cocok dengan lagu. Pilihan diingat per lagu; "Kembali ke otomatis" untuk membatalkan.
- **Shuffle dan repeat** di kiri/kanan tombol kontrol (repeat-one hanya untuk Apple Music).
- **Notifikasi ganti lagu**: saat lagu berganti, notch melebar sebentar menampilkan judul dan artis.
- **Menu ♫ › Isi baris lirik**: teks asli, latin, terjemahan, atau latin + terjemahan (dua baris).
- **Menu ♫ › Sleep timer**: 15/30/45/60 menit atau sampai lagu ini selesai. Ada ikon 🌙 di mode lebar saat aktif.
- **Ikon ♫ di menu bar**: nyalakan/matikan baris lirik di mode ringkas, "Buka saat login", atau keluar dari app.

## Cara kerja

| Bagian | File | Keterangan |
|---|---|---|
| Deteksi lagu | `PlayerMonitor.swift` | Sinyal dari Spotify / Music (instan) + AppleScript tiap 3–6 detik untuk koreksi posisi |
| Lirik | `LyricsStore.swift` | [LRCLIB](https://lrclib.net) (gratis, tanpa API key), format LRC dengan timestamp |
| Cache | `DiskCache.swift` | Lirik & terjemahan di `~/Library/Application Support/NotchLyrics/cache.json` |
| Romanisasi | `Romanizer.swift` | Romaji / latin offline dengan fitur bawaan macOS |
| Terjemahan | `LyricsTranslation.swift` | Translation framework macOS 15+ |
| Window notch | `NotchController.swift` | Panel transparan di atas menu bar; klik tembus kecuali di area hitam |
| Tampilan | `NotchViews.swift` | SwiftUI: mode ringkas, mode lebar, lirik, kontrol |

## Menyimpan project di Git

Supaya kode tidak hanya ada di folder Downloads:

```bash
mkdir -p ~/Developer
mv ~/Downloads/NotchLyrics ~/Developer/
cd ~/Developer/NotchLyrics
git init
git add .
git commit -m "NotchLyrics 1.1"
```

Untuk update berikutnya, ekstrak zip baru ke `~/Developer` dengan `unzip -o NotchLyrics.zip -d ~/Developer`,
lalu `git add . && git commit -m "pesan perubahan"`.
Kalau mau disimpan di GitHub juga (perlu GitHub CLI): `gh repo create NotchLyrics --private --source=. --push`.

## Batasan

- Lirik hanya muncul kalau lagunya ada di database LRCLIB (lagu populer biasanya ada,
  lagu indie/lokal kadang belum). Kalau cuma ada lirik biasa, ditampilkan tanpa sinkron.
- Lirik resmi Spotify / Apple Music tidak bisa diakses karena tidak ada API publiknya.
- Di Mac tanpa notch, app tampil sebagai "pill" di tengah atas layar.

## Ide pengembangan berikutnya

- File shelf (drag & drop file ke notch)
- Indikator volume / brightness
- Event kalender berikutnya
