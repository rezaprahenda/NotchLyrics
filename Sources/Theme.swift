import SwiftUI

/// Satu warna aksen tetap per modul (lihat kanvas desain).
extension Color {
    static let focusAccent = Color(red: 1.0, green: 0.42, blue: 0.34)    // #ff6b57
    static let prayerAccent = Color(red: 0.31, green: 0.82, blue: 0.77)  // #4fd1c5
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
