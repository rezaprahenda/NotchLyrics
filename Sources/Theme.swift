import SwiftUI

/// Satu warna aksen tetap per modul (lihat kanvas desain).
extension Color {
    static let focusAccent = Color(red: 1.0, green: 0.42, blue: 0.34)    // #ff6b57
    static let prayerAccent = Color(red: 0.24, green: 0.80, blue: 0.48)  // #3dcc7a hijau
    static let breakAccent = Color(red: 0.31, green: 0.82, blue: 0.77)   // #4fd1c5 toska (istirahat pomodoro)
    static let deviceAccent = Color(red: 0.20, green: 0.78, blue: 0.35)  // #34c759
    static let shelfAccent = Color(red: 0.35, green: 0.66, blue: 1.0)    // #5aa9ff
    static let reminderAccent = Color(red: 0.35, green: 0.66, blue: 1.0)
}

/// Cincin progres tipis (dipakai di telinga & halaman Fokus).
struct ProgressRing: View {
    let progress: Double
    let color: Color
    var lineWidth: CGFloat = 2

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.22), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

/// Baterai kecil berisi level, dengan petir saat mengisi daya (untuk peek ringkas).
struct BatteryGlyph: View {
    let level: Double
    let charging: Bool

    static func color(level: Double, charging: Bool) -> Color {
        if charging { return .deviceAccent }
        if level <= 0.2 { return Color(red: 1.0, green: 0.27, blue: 0.23) }
        return .white
    }

    var body: some View {
        let color = Self.color(level: level, charging: charging)
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(Color.white.opacity(0.45), lineWidth: 1)
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(color)
                    .frame(width: max(2, 18 * min(max(level, 0), 1)))
                    .padding(1.5)
                if charging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 7, weight: .black))
                        .foregroundStyle(.black.opacity(0.75))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: 22, height: 11)
            RoundedRectangle(cornerRadius: 1).fill(Color.white.opacity(0.45)).frame(width: 1.5, height: 4)
        }
        .accessibilityElement()
        .accessibilityLabel(charging ? L("Mengisi daya", "Charging") : L("Baterai", "Battery"))
    }
}
