import Foundation
import Intents

/// Status mode Focus / Jangan Ganggu macOS (butuh izin "Focus" sekali).
enum FocusStatus {
    static var isFocused: Bool {
        INFocusStatusCenter.default.focusStatus.isFocused ?? false
    }

    static func requestAuthorizationIfNeeded() {
        let center = INFocusStatusCenter.default
        if center.authorizationStatus == .notDetermined {
            center.requestAuthorization { _ in }
        }
    }
}

/// Layar tempat notch ditampilkan.
enum DisplayPreference: String, CaseIterable {
    /// Layar ber-notch kalau ada (MacBook), kalau tidak: layar utama.
    case automatic
    /// Selalu layar utama (yang punya menu bar), mis. saat memakai monitor eksternal.
    case primary

    var title: String {
        switch self {
        case .automatic: return L("Otomatis (layar ber-notch)", "Automatic (notched display)")
        case .primary: return L("Layar utama", "Main display")
        }
    }
}
