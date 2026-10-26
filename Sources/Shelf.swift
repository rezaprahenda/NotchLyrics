import AppKit
import Combine

/// Rak file: tempat transit saat memindahkan file. Menyimpan referensi (path), bukan salinan.
final class ShelfModule: ObservableObject {
    @Published var enabled: Bool = Defaults.bool("shelf.enabled", true) {
        didSet { UserDefaults.standard.set(enabled, forKey: "shelf.enabled") }
    }
    @Published private(set) var items: [URL] = ShelfModule.load()

    func add(_ urls: [URL]) {
        var changed = false
        for url in urls where url.isFileURL && !items.contains(url) {
            items.append(url)
            changed = true
        }
        if changed { save() }
    }

    func remove(_ url: URL) {
        items.removeAll { $0 == url }
        save()
    }

    func clear() {
        items = []
        save()
    }

    /// Buang file yang sudah dipindah / dihapus di luar app.
    func pruneMissing() {
        let existing = items.filter { FileManager.default.fileExists(atPath: $0.path) }
        if existing.count != items.count {
            items = existing
            save()
        }
    }

    func airDrop() {
        guard !items.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        NSApp.activate()
        service.perform(withItems: items)
    }

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func save() {
        UserDefaults.standard.set(items.map(\.path), forKey: "shelf.items")
    }

    private static func load() -> [URL] {
        let paths = UserDefaults.standard.stringArray(forKey: "shelf.items") ?? []
        return paths.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
    }
}
