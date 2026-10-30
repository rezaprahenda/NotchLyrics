import AppKit

/// Ekspresi wajah popocu di ikon menu bar.
enum MenuFace: CaseIterable {
    /// Musik diputar (default).
    case peek
    /// Ada peek: adzan, pomodoro selesai, charger, ganti lagu.
    case lookUp
    /// Berkedip sekali saat app dibuka.
    case wink
    /// Idle atau sleep timer aktif.
    case sleep
    /// Sesi fokus pomodoro berjalan.
    case focus

    var accessibilityLabel: String {
        switch self {
        case .peek: return L("popocu sedang memutar musik", "popocu is playing music")
        case .lookUp: return L("popocu punya kabar", "popocu has news")
        case .wink: return "popocu"
        case .sleep: return L("popocu sedang istirahat", "popocu is resting")
        case .focus: return L("popocu sedang fokus", "popocu is focusing")
        }
    }

    /// Gambar template 18×18 pt (monokrom; macOS mewarnainya sesuai menu bar terang/gelap).
    /// Grid 24×24, sumbu y ke bawah: karakter popocu (kepala + jambul, headphone tipis,
    /// mata sesuai ekspresi, mulut pil). Mata & mulut dibuat dengan "melubangi" bentuknya.
    var image: NSImage {
        let face = self
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current else { return false }
            let scale = NSAffineTransform()
            scale.scale(by: 18.0 / 24.0)
            scale.concat()
            NSColor.black.setFill()
            NSColor.black.setStroke()

            // Headphone, lalu celah tipis di sekeliling kepala supaya keduanya terpisah.
            MenuFace.band().stroke()
            MenuFace.cups().fill()
            ctx.compositingOperation = .destinationOut
            let gap = MenuFace.headShape()
            gap.lineWidth = 2.2
            gap.stroke()
            ctx.compositingOperation = .sourceOver
            MenuFace.headShape().fill()

            // Mata & mulut: dilubangi.
            ctx.compositingOperation = .destinationOut
            face.drawEyes()
            NSBezierPath(roundedRect: NSRect(x: 8.8, y: 17, width: 6.4, height: 2.5), xRadius: 1.25, yRadius: 1.25).fill()
            ctx.compositingOperation = .sourceOver

            face.drawExtras()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = accessibilityLabel
        return image
    }

    /// Kepala bulat-persegi + jambul (notch sebagai poni).
    private static func headShape() -> NSBezierPath {
        let p = NSBezierPath(roundedRect: NSRect(x: 5.6, y: 8, width: 12.8, height: 14), xRadius: 5, yRadius: 5)
        let tuft = NSBezierPath()
        tuft.move(to: NSPoint(x: 10.7, y: 8.6))
        tuft.curve(to: NSPoint(x: 14.6, y: 3), controlPoint1: NSPoint(x: 10.5, y: 5.6), controlPoint2: NSPoint(x: 12.1, y: 3.6))
        tuft.curve(to: NSPoint(x: 14.4, y: 8.6), controlPoint1: NSPoint(x: 13.8, y: 4.6), controlPoint2: NSPoint(x: 13.8, y: 6.5))
        tuft.close()
        p.append(tuft)
        return p
    }

    private static func band() -> NSBezierPath {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: 3.6, y: 13.5))
        p.curve(to: NSPoint(x: 20.4, y: 13.5), controlPoint1: NSPoint(x: 3.6, y: 6.2), controlPoint2: NSPoint(x: 20.4, y: 6.2))
        p.lineWidth = 1.5
        return p
    }

    private static func cups() -> NSBezierPath {
        let p = NSBezierPath(roundedRect: NSRect(x: 2.2, y: 11.6, width: 3.4, height: 6), xRadius: 1.7, yRadius: 1.7)
        p.append(NSBezierPath(roundedRect: NSRect(x: 18.4, y: 11.6, width: 3.4, height: 6), xRadius: 1.7, yRadius: 1.7))
        return p
    }

    private static func line(_ points: [NSPoint], width: CGFloat) {
        guard let first = points.first else { return }
        let p = NSBezierPath()
        p.move(to: first)
        for pt in points.dropFirst() { p.line(to: pt) }
        p.lineWidth = width
        p.lineCapStyle = .round
        p.lineJoinStyle = .round
        p.stroke()
    }

    private static func arc(from a: NSPoint, via c: NSPoint, to b: NSPoint, width: CGFloat) {
        // Kurva kuadrat a→b dengan titik kendali c (dikonversi ke kubik).
        let p = NSBezierPath()
        p.move(to: a)
        p.curve(to: b,
                controlPoint1: NSPoint(x: a.x + (c.x - a.x) * 2 / 3, y: a.y + (c.y - a.y) * 2 / 3),
                controlPoint2: NSPoint(x: b.x + (c.x - b.x) * 2 / 3, y: b.y + (c.y - b.y) * 2 / 3))
        p.lineWidth = width
        p.lineCapStyle = .round
        p.stroke()
    }

    private func drawEyes() {
        switch self {
        case .peek:
            NSBezierPath(ovalIn: NSRect(x: 9.6 - 1.6, y: 13.4 - 1.9, width: 3.2, height: 3.8)).fill()
            NSBezierPath(ovalIn: NSRect(x: 14.4 - 1.6, y: 13.4 - 1.9, width: 3.2, height: 3.8)).fill()
        case .lookUp:
            NSBezierPath(ovalIn: NSRect(x: 9.6 - 2, y: 13.2 - 2, width: 4, height: 4)).fill()
            NSBezierPath(ovalIn: NSRect(x: 14.4 - 2, y: 13.2 - 2, width: 4, height: 4)).fill()
        case .wink:
            MenuFace.arc(from: NSPoint(x: 8.1, y: 14.2), via: NSPoint(x: 9.6, y: 12), to: NSPoint(x: 11.1, y: 14.2), width: 1.4)
            MenuFace.arc(from: NSPoint(x: 12.9, y: 14.2), via: NSPoint(x: 14.4, y: 12), to: NSPoint(x: 15.9, y: 14.2), width: 1.4)
        case .sleep:
            MenuFace.arc(from: NSPoint(x: 8.1, y: 13), via: NSPoint(x: 9.6, y: 14.8), to: NSPoint(x: 11.1, y: 13), width: 1.4)
            MenuFace.arc(from: NSPoint(x: 12.9, y: 13), via: NSPoint(x: 14.4, y: 14.8), to: NSPoint(x: 15.9, y: 13), width: 1.4)
        case .focus:
            MenuFace.line([NSPoint(x: 8.3, y: 12), NSPoint(x: 10.7, y: 13.4), NSPoint(x: 8.3, y: 14.8)], width: 1.3)
            MenuFace.line([NSPoint(x: 15.7, y: 12), NSPoint(x: 13.3, y: 13.4), NSPoint(x: 15.7, y: 14.8)], width: 1.3)
        }
    }

    private func drawExtras() {
        switch self {
        case .lookUp:
            MenuFace.line([NSPoint(x: 19.6, y: 3.6), NSPoint(x: 20.5, y: 1.9)], width: 1.3)
            MenuFace.line([NSPoint(x: 21, y: 5.6), NSPoint(x: 22.7, y: 4.8)], width: 1.3)
        case .sleep:
            MenuFace.line([NSPoint(x: 19.2, y: 2.2), NSPoint(x: 21.6, y: 2.2),
                           NSPoint(x: 19.2, y: 4.6), NSPoint(x: 21.6, y: 4.6)], width: 1.1)
        default:
            break
        }
    }
}
