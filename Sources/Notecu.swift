import AppKit
import SwiftUI
import Combine

/// Jembatan ke notecu: membaca & menulis ke server notecu yang sama (POST /api/sync),
/// jadi catatan dan tugas dari notch langsung muncul di notecu (Mac, iPhone, iPad).
final class NotecuModule: ObservableObject {
    enum Status: Equatable {
        case notConfigured, syncing, ok, offline, badToken
    }

    static let notecuBundleID = "local.notecu.app"

    @Published var serverURL: String = UserDefaults.standard.string(forKey: "notecu.server") ?? "" {
        didSet {
            UserDefaults.standard.set(serverURL, forKey: "notecu.server")
            if serverURL != oldValue { resetForNewServer() }
        }
    }
    @Published var token: String = Keychain.get(account: "notecu.token") ?? "" {
        didSet { Keychain.set(token.trimmingCharacters(in: .whitespacesAndNewlines), account: "notecu.token") }
    }

    @Published private(set) var items: [String: NotecuItem] = [:]
    @Published private(set) var status: Status = .notConfigured
    @Published private(set) var lastSync: Date?
    /// Pesan singkat (mis. "Terkirim" / "Bentrokan disimpan sebagai salinan").
    @Published private(set) var notice: String?

    private var seq = 0
    private var dirty: Set<String> = []
    private var syncing = false
    private var again = false
    private var pollTimer: Timer?
    private var saveWork: DispatchWorkItem?

    init() {
        load()
        setPolling(fast: false)
        if isConfigured { sync() }
    }

    var isConfigured: Bool { baseURL != nil && !cleanToken.isEmpty }
    var isNotecuInstalled: Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.notecuBundleID) != nil }

    private var cleanToken: String { token.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var baseURL: String? {
        var s = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.contains("://") { s = "http://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    // MARK: - Pengaturan dari app notecu

    /// Alamat & token yang sudah diisi di app notecu (kalau terpasang di Mac ini).
    var notecuSettings: (server: String, token: String)? {
        guard let d = UserDefaults.standard.persistentDomain(forName: Self.notecuBundleID),
              let server = d["serverURL"] as? String, !server.isEmpty,
              let token = d["token"] as? String, !token.isEmpty else { return nil }
        return (server, token)
    }

    func importFromNotecu() {
        guard let s = notecuSettings else { return }
        serverURL = s.server
        token = s.token
        sync()
    }

    // MARK: - Data untuk tampilan

    func tasksDue() -> [NotecuItem] {
        NotecuCore.tasksDue(Array(items.values), today: NotecuCore.dayString(Date()))
    }

    func recentNotes(limit: Int = 6) -> [NotecuItem] {
        NotecuCore.recentNotes(Array(items.values), limit: limit)
    }

    // MARK: - Mengubah

    @discardableResult
    func addNote(_ text: String) -> Bool {
        guard let note = NotecuCore.makeNote(from: text) else { return false }
        commit(note)
        flash(L("Tersimpan ke notecu", "Saved to notecu"))
        return true
    }

    @discardableResult
    func addTaskToday(_ title: String) -> Bool {
        guard let task = NotecuCore.makeTask(title: title, due: NotecuCore.dayString(Date())) else { return false }
        commit(task)
        flash(L("Tugas ditambahkan", "Task added"))
        return true
    }

    func toggleDone(_ id: String) {
        guard var t = items[id] else { return }
        t.fields["doneAt"] = t.isDone ? .null : .number(NotecuCore.millis())
        if case .null? = t.fields["doneAt"] { t.fields.removeValue(forKey: "doneAt") }
        commit(t)
    }

    /// Buka app notecu (panelnya muncul dari tepi layar).
    func openNotecu() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.notecuBundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func commit(_ item: NotecuItem) {
        var it = item
        it.updatedAt = max(NotecuCore.millis(), it.updatedAt + 1)
        items[it.id] = it
        dirty.insert(it.id)
        scheduleSave()
        sync()
    }

    private func flash(_ text: String) {
        notice = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            if self?.notice == text { self?.notice = nil }
        }
    }

    // MARK: - Sinkron (aturan sama dengan app notecu)

    /// Cek server lebih sering saat halaman Catatan terbuka.
    func setPolling(fast: Bool) {
        pollTimer?.invalidate()
        let t = Timer(timeInterval: fast ? 10 : 120, repeats: true) { [weak self] _ in self?.sync() }
        RunLoop.main.add(t, forMode: .common)
        pollTimer = t
        if fast { sync() }
    }

    func sync() {
        guard isConfigured, let base = baseURL, let url = URL(string: base + "/api/sync") else {
            status = .notConfigured
            return
        }
        if syncing { again = true; return }
        syncing = true
        status = .syncing

        let sent = dirty.compactMap { items[$0] }
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(cleanToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONEncoder().encode(SyncRequest(after: seq, items: sent))

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async { self?.finish(sent: sent, data: data, response: response, error: error) }
        }.resume()
    }

    /// Tes koneksi untuk tombol di Pengaturan.
    func testConnection(_ done: @escaping (String) -> Void) {
        guard let base = baseURL, let url = URL(string: base + "/api/sync?after=999999999") else {
            return done(L("Isi alamat server dulu.", "Fill in the server address first."))
        }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("Bearer \(cleanToken)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: request) { _, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let text: String
            switch code {
            case 200: text = L("Tersambung ✓", "Connected ✓")
            case 401: text = L("Token salah.", "Wrong token.")
            default:
                text = error.map { L("Tidak bisa terhubung: \($0.localizedDescription)", "Can't connect: \($0.localizedDescription)") }
                    ?? L("Server menjawab \(code).", "Server replied \(code).")
            }
            DispatchQueue.main.async { done(text) }
        }.resume()
    }

    private func finish(sent: [NotecuItem], data: Data?, response: URLResponse?, error: Error?) {
        syncing = false
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 {
            status = .badToken
            return
        }
        guard error == nil, code == 200, let data,
              let res = try? JSONDecoder().decode(SyncResponse.self, from: data) else {
            status = .offline   // perubahan tetap menunggu di Mac dan dikirim lagi nanti
            return
        }
        for s in sent where items[s.id]?.updatedAt == s.updatedAt { dirty.remove(s.id) }
        for a in res.applied ?? [] { items[a.id]?.rev = a.rev }
        items = NotecuCore.merge(items, incoming: res.items, dirty: dirty)
        if let conflicts = res.conflicts, !conflicts.isEmpty {
            flash(L("\(conflicts.count) bentrokan disimpan sebagai salinan", "\(conflicts.count) conflicts saved as copies"))
        }
        seq = res.seq
        lastSync = Date()
        status = .ok
        scheduleSave()
        if again {
            again = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.sync() }
        } else if !dirty.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.sync() }
        }
    }

    private func resetForNewServer() {
        seq = 0
        items = [:]
        dirty = []
        scheduleSave()
    }

    // MARK: - Simpanan lokal (untuk offline)

    private struct Cache: Codable {
        var server: String
        var seq: Int
        var items: [NotecuItem]
        var dirty: [String]
    }

    private struct SyncRequest: Encodable {
        var after: Int
        var items: [NotecuItem]
    }

    private struct SyncResponse: Decodable {
        struct Applied: Decodable { var id: String; var rev: Int }
        struct Conflict: Decodable { var id: String; var copyId: String }
        var seq: Int
        var items: [NotecuItem]
        var applied: [Applied]?
        var conflicts: [Conflict]?
    }

    private var cacheURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("popocu", isDirectory: true)
            .appendingPathComponent("notecu.json")
    }

    private func load() {
        guard let url = cacheURL, let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode(Cache.self, from: data),
              cache.server == (baseURL ?? "") else { return }
        seq = cache.seq
        items = Dictionary(cache.items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        dirty = Set(cache.dirty)
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let snapshot = Cache(server: baseURL ?? "", seq: seq, items: Array(items.values), dirty: Array(dirty))
        let work = DispatchWorkItem { [weak self] in
            guard let url = self?.cacheURL, let data = try? JSONEncoder().encode(snapshot) else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }
}

// MARK: - Halaman Catatan (versi notecu)

struct NotecuPage: View {
    @ObservedObject var notecu: NotecuModule
    @State private var draft = ""
    @State private var asTask = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 14) {
                column(L("Tugas hari ini", "Due today"), symbol: "checklist") {
                    let tasks = notecu.tasksDue()
                    if tasks.isEmpty {
                        empty(L("Tidak ada tugas untuk hari ini 🎉", "Nothing due today 🎉"))
                    } else {
                        ForEach(tasks) { task in taskRow(task) }
                    }
                }
                column(L("Catatan terbaru", "Recent notes"), symbol: "note.text") {
                    let notes = notecu.recentNotes()
                    if notes.isEmpty {
                        empty(L("Belum ada catatan.", "No notes yet."))
                    } else {
                        ForEach(notes) { note in noteRow(note) }
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)

            HStack(spacing: 8) {
                Button { asTask.toggle() } label: {
                    Image(systemName: asTask ? "checkmark.circle" : "note.text")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .help(asTask ? L("Jadi tugas hari ini (klik untuk ganti ke catatan)", "Becomes a task due today (click for note)")
                             : L("Jadi catatan (klik untuk ganti ke tugas)", "Becomes a note (click for task)"))

                TextField(asTask ? L("Tugas baru untuk hari ini…", "New task for today…")
                                 : L("Catatan baru ke notecu…", "New note to notecu…"), text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .focused($focused)
                    .onSubmit(submit)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.08)))

                statusDot
                if notecu.isNotecuInstalled {
                    PeekButton(title: L("Buka notecu", "Open notecu"), filled: false, tint: .white) { notecu.openNotecu() }
                }
            }
        }
        .overlay(alignment: .top) {
            if let notice = notecu.notice {
                Text(notice)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.16)))
                    .transition(.opacity)
            }
        }
        .onAppear { notecu.setPolling(fast: true) }
        .onDisappear { notecu.setPolling(fast: false) }
    }

    private func submit() {
        let ok = asTask ? notecu.addTaskToday(draft) : notecu.addNote(draft)
        if ok { draft = "" }
    }

    private func column<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 3) { content() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func empty(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(.white.opacity(0.45))
            .padding(.top, 4)
    }

    private func taskRow(_ task: NotecuItem) -> some View {
        let overdue = (task.due ?? "") < NotecuCore.dayString(Date())
        return Button { notecu.toggleDone(task.id) } label: {
            HStack(spacing: 7) {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12))
                    .foregroundStyle(task.isImportant ? Color.focusAccent : .white.opacity(0.7))
                Text(task.displayTitle)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .strikethrough(task.isDone)
                Spacer(minLength: 4)
                if overdue {
                    Text(L("telat", "late")).font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.focusAccent)
                } else if let time = task.dueTime {
                    Text(time.replacingOccurrences(of: ":", with: ".")).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func noteRow(_ note: NotecuItem) -> some View {
        Button { notecu.openNotecu() } label: {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    if note.isPinned { Image(systemName: "pin.fill").font(.system(size: 8)).foregroundStyle(.white.opacity(0.5)) }
                    Text(note.displayTitle).font(.system(size: 12, weight: .medium)).lineLimit(1)
                }
                if !note.snippet.isEmpty {
                    Text(note.snippet).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                }
            }
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var statusDot: some View {
        let (color, help): (Color, String) = {
            switch notecu.status {
            case .ok: return (.deviceAccent, L("Tersinkron", "Synced"))
            case .syncing: return (.white.opacity(0.6), L("Menyinkron…", "Syncing…"))
            case .offline: return (.orange, L("Server tidak terjangkau; catatan disimpan dulu di Mac", "Server unreachable; saved on this Mac for now"))
            case .badToken: return (.red, L("Token salah (lihat Pengaturan)", "Wrong token (see Settings)"))
            case .notConfigured: return (.gray, L("Belum diatur", "Not set up"))
            }
        }()
        return Circle().fill(color).frame(width: 7, height: 7).help(help)
    }
}
