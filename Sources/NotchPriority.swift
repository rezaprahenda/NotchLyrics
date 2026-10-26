import Foundation

// Aturan siapa yang tampil di notch (docs/ROADMAP.md §3). Logika murni, dites di Tests/.

/// Pemilik telinga notch pada satu waktu.
enum EarOwner: Equatable {
    /// Waktu salat baru masuk (±10 menit pertama).
    case prayerNow
    /// Sesi pomodoro berjalan (musik, kalau ada, digabung: cover + ring progres).
    case pomodoro
    /// Musik diputar, atau baru di-pause (< 1 menit).
    case music
    /// Waktu salat berikutnya kurang dari 15 menit lagi.
    case prayerSoon
    /// Musik sudah di-pause lama, tidak ada yang lebih penting.
    case musicIdle
    /// Tidak ada apa-apa: notch kembali seukuran notch fisik.
    case none
}

/// Keadaan semua modul yang relevan untuk memilih pemilik telinga.
struct NotchSituation: Equatable {
    var hasTrack = false
    var isPlaying = false
    /// Sudah berapa lama musik di-pause (detik). Diabaikan saat memutar.
    var pausedFor: TimeInterval = 0
    var pomodoroRunning = false
    /// Menit sejak waktu salat terakhir masuk (nil = belum ada / modul mati).
    var minutesSincePrayer: Double?
    /// Menit menuju waktu salat berikutnya (nil = modul mati).
    var minutesToPrayer: Double?
}

enum NotchPriority {
    static let prayerNowWindow: Double = 10      // menit
    static let prayerSoonWindow: Double = 15     // menit
    static let musicIdleAfter: TimeInterval = 60 // detik

    static func earOwner(_ s: NotchSituation) -> EarOwner {
        if let since = s.minutesSincePrayer, since >= 0, since < prayerNowWindow { return .prayerNow }
        if s.pomodoroRunning { return .pomodoro }
        if s.hasTrack && (s.isPlaying || s.pausedFor < musicIdleAfter) { return .music }
        if let to = s.minutesToPrayer, to >= 0, to < prayerSoonWindow { return .prayerSoon }
        if s.hasTrack { return .musicIdle }
        return .none
    }
}

// MARK: - Antrian peek

/// Kejadian singkat yang ditampilkan sebagai peek.
struct PeekEvent: Equatable {
    /// Urutan = prioritas (makin besar makin penting).
    enum Kind: Int, Comparable {
        case trackChange = 0
        case reminder = 1    // minum, berdiri
        case device = 2      // charger, baterai, AirPods
        case pomodoro = 3
        case prayer = 4

        static func < (a: Kind, b: Kind) -> Bool { a.rawValue < b.rawValue }

        /// Berapa lama peek tampil (detik).
        var duration: TimeInterval {
            switch self {
            case .prayer: return 10
            case .pomodoro: return 8
            case .reminder: return 5
            case .device, .trackChange: return 3
            }
        }
    }

    let kind: Kind
    /// Penanda isi (mis. key lagu), untuk membuang duplikat.
    let id: String
    let createdAt: Date
    var title = ""
    var subtitle = ""
}

/// Satu peek tampil pada satu waktu; sisanya antre (maks. 3) menurut prioritas.
struct PeekQueue {
    static let capacity = 3
    private(set) var items: [PeekEvent] = []

    mutating func push(_ event: PeekEvent) {
        // Kejadian sejenis yang lebih lama sudah basi (mis. lagu sudah berganti lagi).
        items.removeAll { $0.kind == event.kind }
        items.append(event)
        // Prioritas tertinggi dulu; sama prioritas → yang lebih dulu terjadi.
        items.sort { $0.kind != $1.kind ? $0.kind > $1.kind : $0.createdAt < $1.createdAt }
        if items.count > Self.capacity { items.removeLast(items.count - Self.capacity) }
    }

    /// Ambil peek berikutnya untuk ditampilkan.
    mutating func next() -> PeekEvent? {
        items.isEmpty ? nil : items.removeFirst()
    }

    var isEmpty: Bool { items.isEmpty }
}
