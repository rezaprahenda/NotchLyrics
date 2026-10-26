import SwiftUI
import Translation

/// View tak terlihat yang menjalankan Translation framework (macOS 15+).
/// Translation hanya bisa dipakai lewat modifier SwiftUI `.translationTask`, jadi view ini
/// ditempel di root notch dan dipicu setiap `translationRequestID` berubah.
@available(macOS 15.0, *)
struct TranslationRunner: View {
    @ObservedObject var lyrics: LyricsStore
    @State private var configuration: TranslationSession.Configuration?
    @State private var configuredTarget: String?

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .translationTask(configuration) { session in
                await lyrics.translate(using: session)
            }
            .onChange(of: lyrics.translationRequestID, initial: true) { _, _ in
                guard lyrics.wantsTranslation,
                      !lyrics.translatableLines.isEmpty,
                      lyrics.translations.isEmpty
                else { return }
                let target = lyrics.translationTarget
                if configuration == nil || configuredTarget != target {
                    // Bahasa sumber dideteksi otomatis; target sesuai pilihan di menu.
                    configuredTarget = target
                    configuration = TranslationSession.Configuration(
                        source: nil,
                        target: Locale.Language(identifier: target)
                    )
                } else {
                    configuration?.invalidate() // jalankan ulang untuk lagu baru
                }
            }
    }
}

@available(macOS 15.0, *)
extension LyricsStore {
    func translate(using session: TranslationSession) async {
        let snapshot = await MainActor.run { (self.translationKey, self.translatableLines, self.wantsTranslation) }
        guard let key = snapshot.0, snapshot.2, !snapshot.1.isEmpty else { return }

        await MainActor.run { self.setTranslationStatus(.translating) }

        let requests = snapshot.1.map {
            TranslationSession.Request(sourceText: $0.1, clientIdentifier: String($0.0))
        }
        do {
            let responses = try await session.translations(from: requests)
            var map: [Int: String] = [:]
            for r in responses {
                guard let idString = r.clientIdentifier, let id = Int(idString) else { continue }
                let text = r.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
                // Lewati baris yang hasilnya sama (mis. sudah bahasa Indonesia, atau cuma "oh oh").
                if !text.isEmpty, text.lowercased() != r.sourceText.lowercased() {
                    map[id] = text
                }
            }
            let result = map // salinan konstan supaya aman dikirim ke main actor
            await MainActor.run { self.applyTranslations(result, key: key) }
        } catch {
            let message = error.localizedDescription
            await MainActor.run {
                guard self.translationKey == key else { return }
                self.setTranslationStatus(.failed(message))
            }
        }
    }
}

/// Tombol "ID" di pojok kanan atas lirik untuk menyalakan / mematikan terjemahan.
struct TranslateToggle: View {
    @ObservedObject var lyrics: LyricsStore

    var body: some View {
        Button {
            lyrics.translationEnabled.toggle()
        } label: {
            HStack(spacing: 3) {
                if lyrics.translationStatus == .translating {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.6)
                        .frame(width: 10, height: 10)
                } else {
                    Image(systemName: "translate")
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(String(lyrics.translationTarget.prefix(2)).uppercased())
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(.white.opacity(lyrics.translationEnabled ? 1 : 0.55))
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(Capsule().fill(Color.white.opacity(lyrics.translationEnabled ? 0.22 : 0.08)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(L("Terjemahkan lirik ke \(languageName(lyrics.translationTarget))",
                "Translate lyrics to \(languageName(lyrics.translationTarget))"))
    }
}

/// Pesan kecil kalau terjemahan gagal.
struct TranslationErrorNote: View {
    @ObservedObject var lyrics: LyricsStore

    var body: some View {
        if lyrics.translationEnabled, case .failed(let message) = lyrics.translationStatus {
            Text(note(for: message))
                .font(.system(size: 10))
                .foregroundStyle(Color.orange.opacity(0.85))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.black.opacity(0.85)))
        }
    }

    private func note(for message: String) -> String {
        if message == lyrics.alreadyTranslatedMessage { return message }
        let name = languageName(lyrics.translationTarget)
        return L("Terjemahan gagal. Unduh bahasa \(name) di System Settings › General › Language & Region › Translation Languages.",
                 "Translation failed. Download \(name) in System Settings › General › Language & Region › Translation Languages.")
    }
}
