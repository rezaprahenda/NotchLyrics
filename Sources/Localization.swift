import Foundation

/// Bahasa tampilan app. `.system` mengikuti bahasa utama macOS.
enum AppLanguage: String, CaseIterable {
    case system, en, id

    static let defaultsKey = "appLanguage"

    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .system
    }

    /// Dibaca sekali saat app dibuka; mengganti bahasa memerlukan buka ulang app.
    static let isIndonesian: Bool = {
        switch current {
        case .id: return true
        case .en: return false
        case .system: return Locale.preferredLanguages.first?.hasPrefix("id") ?? false
        }
    }()

    var title: String {
        switch self {
        case .system: return L("Ikuti sistem", "Follow system")
        case .en: return "English"
        case .id: return "Bahasa Indonesia"
        }
    }
}

/// Teks UI dalam dua bahasa: `L("Indonesia", "English")`.
func L(_ indonesian: String, _ english: String) -> String {
    AppLanguage.isIndonesian ? indonesian : english
}

/// Nama bahasa (mis. "Jepang" / "Japanese") dalam bahasa tampilan app.
func languageName(_ code: String) -> String {
    let ui = Locale(identifier: AppLanguage.isIndonesian ? "id" : "en")
    return ui.localizedString(forIdentifier: code) ?? code
}
