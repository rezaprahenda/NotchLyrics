# Roadmap & Rancangan Pengalaman

Dokumen ini memetakan semua fitur yang direncanakan, di mana masing-masing tampil di notch,
dan aturan supaya fitur-fitur itu tidak saling bertabrakan. Nama app masih sementara
(kandidat: **Poni**, Alis, Pucuk, Atap).

---

## 1. Prinsip

1. **Tenang secara default.** Sehari-hari notch hanya menampilkan satu hal. Notch melebar hanya kalau ada sesuatu yang perlu dilihat.
2. **Satu hal per tempat, satu waktu.** Setiap area notch punya satu pemilik pada satu waktu, ditentukan oleh prioritas (lihat §3).
3. **Kejadian itu sementara.** Ganti lagu, charger, AirPods, adzan, dan pomodoro selesai muncul sebagai *peek* singkat lalu hilang sendiri.
4. **Semua modul opsional.** Setiap fitur bisa dimatikan. Izin (lokasi, kalender) baru diminta saat modulnya dinyalakan.
5. **Tidak menghalangi kerja.** Menu bar app lain harus tetap bisa diakses. Notch tidak boleh ikut terlihat saat share screen kalau pengguna tidak mau.
6. **Privasi & hemat baterai.** Semua dihitung di perangkat kalau memungkinkan (jadwal salat, terjemahan). Tidak ada polling yang tidak perlu.

---

## 2. Permukaan (tempat tampil)

| Permukaan | Ukuran | Fungsi | Contoh isi |
|---|---|---|---|
| **Telinga kiri** | ±70 pt di kiri notch | Identitas / ikon | Cover album, ikon 🍅, ikon masjid |
| **Telinga kanan** | ±70 pt di kanan notch | Angka / status | Equalizer, `18:42`, `Asr 14m` |
| **Baris bawah** | 1–2 baris di bawah notch | Konten berjalan | Lirik (+karaoke), garis progres pomodoro |
| **Peek** | Melebar ±3 detik | Kejadian | "Lagu baru", "⚡ 64%", "Waktunya Dzuhur" |
| **Panel penuh** (hover) | ±500×250 pt | Kontrol & detail | Halaman: Musik · Fokus · Salat · Rak file |
| **Menu bar icon** | — | Akses cepat | Buka pengaturan, keluar |
| **Jendela Pengaturan** | Jendela biasa | Semua opsi | Per modul, bahasa, shortcut |

Catatan: menu di menu bar sekarang sudah panjang. Di 2.0 pengaturan pindah ke **jendela
Pengaturan** (tab per modul), dan menu di menu bar tinggal berisi aksi cepat.

---

## 3. Prioritas & aturan tabrakan

### Pemilik telinga (tertinggi → terendah)

1. **Adzan sedang berlangsung** (selama ±10 menit sejak waktu salat masuk)
2. **Pomodoro berjalan** → kiri 🍅 + ring progres, kanan sisa waktu.
   Kalau musik juga diputar, keduanya digabung: **kiri = cover dengan ring progres pomodoro**,
   **kanan = sisa waktu**, dan lirik tetap jalan di baris bawah.
3. **Musik diputar** → kiri cover, kanan equalizer
4. **Hitung mundur salat** (hanya saat < 15 menit lagi)
5. Kosong (notch kembali seukuran notch fisik)

Musik yang di-pause lebih dari 1 menit turun ke bawah urutan nomor 4.

### Baris bawah

- Lirik selalu menang kalau ada lirik tersinkron dan opsinya aktif.
- Kalau pomodoro berjalan bersamaan dengan lirik, progres pomodoro tampil sebagai **garis tipis di tepi bawah**, bukan sebagai baris sendiri.

### Antrian peek

- Hanya satu peek tampil pada satu waktu. Sisanya antre, maksimal 3. Peek yang sudah basi dibuang (mis. "ganti lagu" yang sudah lewat lagi).
- Prioritas: adzan > pomodoro selesai > charger/AirPods > ganti lagu.
- Peek tidak muncul saat panel penuh terbuka atau saat share screen (kalau disembunyikan).

### Sinkronisasi antar modul

| Kejadian | Efek ke modul lain |
|---|---|
| Waktu salat masuk | Pomodoro dijeda otomatis. Musik di-pause (opsi). Peek adzan (+suara, opsi). |
| Pomodoro: fokus → istirahat | Musik **tidak disentuh** (default). Opsi: pause saat istirahat, atau pause saat fokus. Peek "Istirahat 5 menit". |
| Share screen / rekam layar | Semua permukaan disembunyikan (opsi). Event tetap dicatat. |
| Jendela app penuh di bawah notch | Baris bawah disembunyikan (sudah ada). |
| Kursor di atas telinga | Sisi itu (telinga + bagian baris di bawahnya) hilang. Konten pindah ke sisi lain. |
| File diseret mendekati notch | Notch membuka "Rak file" sebagai target drop, menggantikan apa pun yang sedang tampil. |
| Charger dicolok / dicabut | Peek baterai. Kalau baterai < 10% dan tidak dicas: peek peringatan. |

---

## 4. Interaksi

| Gerakan | Hasil |
|---|---|
| Hover notch | Panel penuh (halaman terakhir dibuka) |
| Hover telinga di menu bar | Sisi itu disembunyikan otomatis (jeda 0,15 detik) supaya menu app di bawahnya bisa diklik |
| Kursor mendekati baris lirik | Baris memudar & tembus klik (sudah ada) |
| Klik baris lirik (panel penuh) | Seek ke baris itu (sudah ada) |
| Swipe 2 jari kiri/kanan di panel penuh | Ganti halaman modul |
| Seret file ke notch | Simpan di Rak file |
| Seret file keluar dari Rak | Pindah / salin ke tujuan |
| Shortcut global | ⌥⌘L lirik on/off · ⌥⌘[ / ] offset lirik · ⌥⌘P mulai/jeda pomodoro |

---

## 5. Peta modul

| Modul | Telinga | Baris | Peek | Panel penuh | Izin | Rilis |
|---|---|---|---|---|---|---|
| Lirik & musik | cover · equalizer | lirik | ganti lagu | lirik penuh + kontrol | Automation (Spotify/Music) | ✅ |
| Karaoke (opsi) | — | isi warna per baris | — | tombol on/off | — | 1.3 |
| Warna cover (opsi) | warna equalizer | warna aksen | — | — | — | 1.3 |
| Sembunyi saat share screen | semua | semua | semua | — | — | 1.3 |
| Shortcut keyboard | — | — | — | — | — | 1.3 |
| Pomodoro | 🍅 · sisa waktu | garis progres | selesai/istirahat | preset, statistik | — | 2.0 |
| Waktu salat & adzan | ikon · hitung mundur | — | adzan | jadwal hari ini | Lokasi (atau kota manual) | 2.0 |
| Rak file | jumlah file | — | — | daftar file, AirDrop | — | 2.0 |
| Baterai & AirPods | — | — | ⚡ %, AirPods % | — | Bluetooth (AirPods) | 2.0 |
| Last.fm | — | — | — | status scrobble | Login Last.fm | 2.x |
| Salin/bagikan lirik | — | — | — | klik kanan baris | — | 2.x |

---

## 6. Ide tambahan (dinilai)

| Ide | Nilai | Catatan |
|---|---|---|
| **Mode Ramadan**: imsak, hitung mundur buka puasa | ⭐⭐⭐ | Memakai ulang perhitungan jadwal salat |
| **Rapat berikutnya** dari Kalender + tombol join (Zoom/Meet) | ⭐ | Butuh izin Kalender. Belum dipakai pemilik; tunda |
| **Tanggal Hijriah** di panel salat | ⭐⭐ | Kalender `islamicUmmAlQura` bawaan Foundation |
| **Catatan cepat** (1 catatan tempel di panel) | ⭐⭐ | Simpel, berguna |
| **Riwayat clipboard** (10 item) | ⭐⭐ | Hati-hati dengan password: lewati item dari password manager |
| **Jam dunia / zona waktu kedua** | ⭐ | Untuk kerja lintas negara |
| **Pengingat minum / berdiri** | ⭐ | Bisa digabung ke pomodoro |
| Kamera cermin (cek penampilan sebelum meeting) | ⭐ | Butuh izin kamera |
| Ganti HUD volume/brightness bawaan | ✖ | Butuh API privat, rawan rusak tiap update macOS |
| Now playing dari browser (YouTube) | ✖ | API MediaRemote ditutup sejak macOS 15.4 |
| Cuaca | ✖ | Butuh API key/servis luar. Kurang cocok dengan prinsip privasi |

---

## 7. Arsitektur (untuk 2.0)

- **`NotchModule` protocol**: setiap modul menyediakan `earContent`, `lineContent`, `expandedPage`, `priority`, dan mengirim `NotchEvent` untuk peek.
- **`NotchCoordinator`**: satu-satunya yang memutuskan siapa pemilik telinga, baris, dan peek (aturan §3). View hanya merender hasilnya.
- **`EventBus`**: kejadian lintas modul (salat masuk, pomodoro ganti fase, share screen). Modul lain bereaksi tanpa saling kenal.
- **Pengaturan** per modul di `UserDefaults` dengan prefiks (`prayer.method`, `pomodoro.focusMinutes`).
- **Anggaran energi**: tidak ada timer ≤ 1 detik kecuali sedang tampil. Jadwal salat dihitung sekali per hari. Pomodoro memakai satu `Timer` ke titik berikutnya, bukan detak terus-menerus.

---

## 8. Urutan rilis

1. **1.2** (selesai, menunggu build & tes): akurasi lirik, retry jaringan, hemat baterai, telinga per sisi, lokalisasi en/id, bahasa terjemahan, hapus cache.
2. **1.3**: karaoke (opsi), warna cover (opsi), sembunyi saat share screen, hide per sisi penuh (telinga + baris), shortcut keyboard.
3. **2.0, nama baru**: arsitektur modul, jendela Pengaturan, Pomodoro, Salat & adzan (+mode Ramadan), Rak file, Baterai & AirPods.
4. **2.x**: Last.fm, salin/bagikan lirik, catatan cepat, clipboard. Kalender nanti saja, kalau dibutuhkan.
