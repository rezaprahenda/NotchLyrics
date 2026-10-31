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
    @Environment(\.panelStyle) private var style

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content.background {
            ZStack {
                if style == .glass {
                    // Di atas kaca: kartu hampir bening, cukup garis tipis, supaya kacanya tetap terasa.
                    shape.fill(tint?.opacity(0.07) ?? Color.white.opacity(0.025))
                    shape.strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
                } else if style == .plain {
                    shape.fill(tint?.opacity(0.12) ?? Color.white.opacity(0.06))
                } else if reduceTransparency {
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
    @Environment(\.panelStyle) private var style

    func body(content: Content) -> some View {
        let on = enabled && !reduceTransparency && style == .vivid
        content.shadow(color: on ? color.opacity(0.55) : .clear, radius: radius)
    }
}

/// Cincin progres tebal bergradasi dengan glow (halaman Fokus).
struct GlowRing: View {
    let progress: Double
    let color: Color
    var lineWidth: CGFloat = 10
    @Environment(\.panelStyle) private var style

    var body: some View {
        let p = min(max(progress, 0), 1)
        ZStack {
            // Di atas kaca terang jalurnya perlu lebih tegas.
            Circle().stroke(Color.white.opacity(style == .glass ? 0.18 : 0.08), lineWidth: lineWidth)
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

// MARK: - Gaya panel (Pengaturan › Notch › Gaya)

enum PanelStyle: String, CaseIterable {
    /// Gradasi gelap + kartu berlapis + satu cahaya per halaman (bawaan).
    case vivid
    /// Bagian di bawah menu bar memakai kaca gelap buram.
    case glass
    /// Hitam rata tanpa cahaya.
    case plain

    var title: String {
        switch self {
        case .vivid: return L("Hidup", "Vivid")
        case .glass: return L("Kaca", "Glass")
        case .plain: return L("Polos", "Plain")
        }
    }
}

private struct PanelStyleKey: EnvironmentKey {
    static let defaultValue: PanelStyle = .vivid
}

extension EnvironmentValues {
    var panelStyle: PanelStyle {
        get { self[PanelStyleKey.self] }
        set { self[PanelStyleKey.self] = newValue }
    }
}

/// Kaca buram bawaan macOS (memburamkan apa pun di belakang jendela notch).
///
/// Dipasang langsung di jendela, di bawah tampilan SwiftUI. Kalau ditaruh di dalam SwiftUI
/// (yang memakai mask/clip/bayangan), macOS menggambarnya di luar layar dan kacanya jadi abu-abu polos.
final class GlassView: NSVisualEffectView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        isEmphasized = false
        appearance = NSAppearance(named: .darkAqua)
        alphaValue = 0
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) tidak dipakai") }

    /// Klik selalu diteruskan ke SwiftUI di atasnya.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Topeng seukuran kaca: atas lurus, dua sudut bawah membulat. Dibuat persis seukuran bingkainya
    /// (topeng yang "melar" lewat capInsets ternyata tidak selalu dihormati → sudut jadi lonjong).
    /// Radius sedikit dibesarkan supaya kaca tidak mengintip di luar sudut "continuous" panel.
    /// `ear` > 0: kolom telinga kiri/kanan selebar itu memudar sesuai `fades` (telinga musik yang
    /// ditunjuk/disingkirkan), sama dengan masker SwiftUI di NotchRootView supaya kaca dan lapisan
    /// gelapnya tidak "patah".
    static func mask(size: CGSize, radius: CGFloat, ear: CGFloat = 0, fades: EarFades = EarFades()) -> NSImage {
        let w = max(size.width, 1), h = max(size.height, 1)
        let r = min(max(radius * 1.15, 1), min(w, h) / 2)
        return NSImage(size: NSSize(width: w, height: h), flipped: false) { rect in
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 0, y: rect.maxY))
            path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
            path.line(to: NSPoint(x: rect.maxX, y: r))
            path.appendArc(withCenter: NSPoint(x: rect.maxX - r, y: r), radius: r, startAngle: 0, endAngle: 270, clockwise: true)
            path.line(to: NSPoint(x: r, y: 0))
            path.appendArc(withCenter: NSPoint(x: r, y: r), radius: r, startAngle: 270, endAngle: 180, clockwise: true)
            path.close()
            path.addClip()
            let e = min(max(ear, 0), w / 2)
            // Tengah: sudut bawah di sisi telinga yang disingkirkan ikut membulat; sisanya bayangan tipis.
            let middle = NSRect(x: e, y: 0, width: w - 2 * e, height: h)
            let cornerLimit = min(r, middle.width / 2, h)
            let cl = fades.left.corner * cornerLimit, cr = fades.right.corner * cornerLimit
            if cl > 0 || cr > 0 {
                NSColor.black.withAlphaComponent(0.12).setFill()
                NSBezierPath(rect: middle).fill()
            }
            NSColor.black.setFill()
            bottomRounded(middle, left: cl, right: cr).fill()
            if e > 0 {
                let black = { (a: CGFloat) in NSColor.black.withAlphaComponent(a) }
                NSGradient(starting: black(fades.left.outer), ending: black(fades.left.inner))?
                    .draw(in: NSRect(x: 0, y: 0, width: e, height: h), angle: 0)
                NSGradient(starting: black(fades.right.inner), ending: black(fades.right.outer))?
                    .draw(in: NSRect(x: w - e, y: 0, width: e, height: h), angle: 0)
            }
            return true
        }
    }
}

/// Persegi dengan atas lurus dan sudut bawah membulat sesuai radius masing-masing (0 = kotak).
private func bottomRounded(_ r: NSRect, left: CGFloat, right: CGFloat) -> NSBezierPath {
    let p = NSBezierPath()
    p.move(to: NSPoint(x: r.minX, y: r.maxY))
    p.line(to: NSPoint(x: r.maxX, y: r.maxY))
    if right > 0 {
        p.line(to: NSPoint(x: r.maxX, y: r.minY + right))
        p.appendArc(withCenter: NSPoint(x: r.maxX - right, y: r.minY + right), radius: right,
                    startAngle: 0, endAngle: 270, clockwise: true)
    } else {
        p.line(to: NSPoint(x: r.maxX, y: r.minY))
    }
    if left > 0 {
        p.line(to: NSPoint(x: r.minX + left, y: r.minY))
        p.appendArc(withCenter: NSPoint(x: r.minX + left, y: r.minY + left), radius: left,
                    startAngle: 270, endAngle: 180, clockwise: true)
    } else {
        p.line(to: NSPoint(x: r.minX, y: r.minY))
    }
    p.close()
    return p
}

/// Kepekatan satu kolom telinga: tepi luar & tepi yang menempel notch (1 = pekat).
/// `corner`: seberapa membulat sudut bawah bagian tengah di sisi ini (0–1), saat telinga disingkirkan.
struct EarFade: Equatable {
    var outer: CGFloat = 1
    var inner: CGFloat = 1
    var corner: CGFloat = 0

    func mix(_ to: EarFade, _ t: CGFloat) -> EarFade {
        EarFade(outer: outer + (to.outer - outer) * t,
                inner: inner + (to.inner - inner) * t,
                corner: corner + (to.corner - corner) * t)
    }
}

struct EarFades: Equatable {
    var left = EarFade()
    var right = EarFade()
}

/// Latar notch sesuai gaya. Area setinggi notch fisik selalu hitam pekat.
struct NotchFill: View {
    let style: PanelStyle
    /// Panel penuh / peek lebar (bergradasi) — selain itu telinga + baris lirik.
    let deep: Bool
    let notchHeight: CGFloat
    let totalHeight: CGFloat
    /// Kegelapan lapisan kaca (Pengaturan › Notch), 0,15–0,75.
    var glassDarkness: Double = 0.35

    var body: some View {
        switch style {
        case .plain:
            Color.black
        case .vivid:
            if deep {
                PanelBackground.gradient(notchHeight: notchHeight, totalHeight: totalHeight)
            } else {
                Color.black
            }
        case .glass:
            // Kaca utuh: seluruh panel (termasuk di samping notch) kaca dengan satu warna rata.
            // Notch fisik tetap hitam sendiri, seperti pulau di atas lembaran kaca.
            Color.black.opacity(deep ? glassDarkness : min(glassDarkness + 0.1, 0.85))
        }
    }
}

/// Aset merek popocu.
enum Brand {
    /// Karakter popocu tanpa kotak (Resources/Mascot.png); cadangan: ikon app.
    static let mascot: NSImage = Bundle.main.image(forResource: "Mascot") ?? NSApp.applicationIconImage
}

/// Bayangan lembut di sekeliling panel kaca. Bagian di dalam panel dilubangi (mask even-odd),
/// jadi bayangan tidak menggelapkan kacanya sendiri.
final class GlassShadowView: NSView {
    private let shadowLayer = CALayer()
    private let maskLayer = CAShapeLayer()
    private let pad: CGFloat = 28

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        alphaValue = 0
        shadowLayer.shadowColor = NSColor.black.cgColor
        shadowLayer.shadowOpacity = 0.28
        shadowLayer.shadowRadius = 10
        shadowLayer.shadowOffset = CGSize(width: 0, height: -4)
        layer?.addSublayer(shadowLayer)
        maskLayer.fillRule = .evenOdd
        layer?.mask = maskLayer
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) tidak dipakai") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(panel: NSRect, radius: CGFloat) {
        frame = panel.insetBy(dx: -pad, dy: -pad)
        let local = NSRect(x: pad, y: pad, width: panel.width, height: panel.height)
        let path = Self.panelPath(local, radius: radius)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shadowLayer.frame = bounds
        shadowLayer.shadowPath = path
        let m = CGMutablePath()
        m.addRect(bounds)
        m.addPath(path)
        maskLayer.frame = bounds
        maskLayer.path = m
        CATransaction.commit()
    }

    /// Atas lurus, dua sudut bawah membulat (koordinat y ke atas).
    static func panelPath(_ r: NSRect, radius: CGFloat) -> CGPath {
        let rad = min(radius, r.width / 2, r.height / 2)
        let p = CGMutablePath()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + rad))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX - rad, y: r.minY), radius: rad)
        p.addLine(to: CGPoint(x: r.minX + rad, y: r.minY))
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.minX, y: r.minY + rad), radius: rad)
        p.closeSubpath()
        return p
    }
}
