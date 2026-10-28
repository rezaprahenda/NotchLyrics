import SwiftUI
import AppKit

/// Satu warna aksen tetap per modul (lihat kanvas desain).
extension Color {
    static let focusAccent = Color(red: 1.0, green: 0.42, blue: 0.34)    // #ff6b57
    static let prayerAccent = Color(red: 0.24, green: 0.80, blue: 0.48)  // #3dcc7a hijau
    static let breakAccent = Color(red: 0.31, green: 0.82, blue: 0.77)   // #4fd1c5 toska (istirahat pomodoro)
    static let deviceAccent = Color(red: 0.20, green: 0.78, blue: 0.35)  // #34c759
    static let shelfAccent = Color(red: 0.35, green: 0.66, blue: 1.0)    // #5aa9ff
    static let reminderAccent = Color(red: 0.35, green: 0.66, blue: 1.0)
    static let musicAccent = Color(red: 1.0, green: 0.37, blue: 0.54)     // #ff5e8a merah muda (tanpa lagu)
    static let mirrorAccent = Color(red: 0.65, green: 0.55, blue: 0.98)   // #a78bfa ungu
    static let clipboardAccent = Color(red: 0.96, green: 0.71, blue: 0.16) // #f5b42a kuning popocu
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

// MARK: - Kedalaman visual (lihat papan "Kedalaman visual" di kanvas desain)

extension Color {
    /// Ujung bawah gradasi panel penuh; bagian atas tetap hitam supaya menyatu dengan notch fisik.
    static let panelBottom = Color(red: 0.09, green: 0.09, blue: 0.10)  // #17171a

    /// Versi lebih terang dari warna ini (untuk ujung gradasi & teks aksen di atas latar gelap).
    func lighter(_ amount: CGFloat = 0.4) -> Color {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        return Color(nsColor: ns.blended(withFraction: amount, of: .white) ?? ns)
    }
}

/// Latar panel penuh: hitam pekat di area notch, sedikit terang ke bawah.
struct PanelBackground {
    static func gradient(notchHeight: CGFloat, totalHeight: CGFloat) -> LinearGradient {
        let solid = totalHeight > 0 ? min(max(notchHeight / totalHeight + 0.08, 0), 0.6) : 0.25
        // Naik pelan (ease-in) supaya tidak terlihat garis di tempat gradasi mulai.
        let steps = 8
        var stops: [Gradient.Stop] = [.init(color: .black, location: 0), .init(color: .black, location: solid)]
        for i in 1...steps {
            let t = Double(i) / Double(steps)
            let eased = t * t * (3 - 2 * t) // smoothstep
            let v = 0.09 * eased, b = 0.10 * eased
            stops.append(.init(color: Color(red: v, green: v, blue: b), location: solid + (1 - solid) * t))
        }
        return LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
    }
}

/// Kartu permukaan: sedikit lebih terang dari latar, dengan kilau 1 px di tepi atas.
/// `tint` memberi cahaya warna dari pojok kiri atas (dipakai kartu "berikutnya").
struct SurfaceCard: ViewModifier {
    var tint: Color? = nil
    var radius: CGFloat = 14
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content.background {
            ZStack {
                if reduceTransparency {
                    shape.fill(tint?.opacity(0.18) ?? Color(white: 0.11))
                } else {
                    shape.fill(LinearGradient(colors: [.white.opacity(0.075), .white.opacity(0.035)],
                                              startPoint: .top, endPoint: .bottom))
                    if let tint {
                        shape.fill(RadialGradient(colors: [tint.opacity(0.28), tint.opacity(0.04)],
                                                  center: .topLeading, startRadius: 0, endRadius: 190))
                    }
                    shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.10), .white.opacity(0.03)],
                                                      startPoint: .top, endPoint: .bottom), lineWidth: 1)
                }
            }
        }
    }
}

extension View {
    func surfaceCard(tint: Color? = nil, radius: CGFloat = 14) -> some View {
        modifier(SurfaceCard(tint: tint, radius: radius))
    }

    /// Cahaya halus berwarna; mati saat Reduce Transparency.
    func softGlow(_ color: Color, radius: CGFloat = 6, enabled: Bool = true) -> some View {
        modifier(SoftGlow(color: color, radius: radius, enabled: enabled))
    }
}

struct SoftGlow: ViewModifier {
    let color: Color
    let radius: CGFloat
    let enabled: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content.shadow(color: (enabled && !reduceTransparency) ? color.opacity(0.55) : .clear, radius: radius)
    }
}

/// Cincin progres tebal bergradasi dengan glow (halaman Fokus).
struct GlowRing: View {
    let progress: Double
    let color: Color
    var lineWidth: CGFloat = 10

    var body: some View {
        let p = min(max(progress, 0), 1)
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [color.opacity(0.16), .clear], center: .init(x: 0.5, y: 0.35),
                                     startRadius: 0, endRadius: 70))
                .padding(lineWidth)
            Circle().stroke(Color.white.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: p)
                .stroke(LinearGradient(colors: [color.lighter(0.5), color, color.opacity(0.9)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .softGlow(color, radius: 7, enabled: p > 0)
        }
    }
}
