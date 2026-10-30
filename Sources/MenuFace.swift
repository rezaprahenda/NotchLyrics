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
    /// Digambar dalam grid 24×24 dengan sumbu y ke bawah: notch kecil di atas + gelembung pop (logo popocu).
    var image: NSImage {
        let face = self
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            let scale = NSAffineTransform()
            scale.scale(by: 18.0 / 24.0)
            scale.concat()
            NSColor.black.setFill()
            NSColor.black.setStroke()
            MenuFace.notch().fill()
            face.drawBubble()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = accessibilityLabel
        return image
    }

    /// Notch kecil: atas lurus, dua sudut bawah membulat.
    private static func notch() -> NSBezierPath {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: 6, y: 2))
        p.line(to: NSPoint(x: 18, y: 2))
        p.line(to: NSPoint(x: 18, y: 4.2))
        p.curve(to: NSPoint(x: 15.7, y: 6.5), controlPoint1: NSPoint(x: 18, y: 5.73), controlPoint2: NSPoint(x: 17.23, y: 6.5))
        p.line(to: NSPoint(x: 8.3, y: 6.5))
        p.curve(to: NSPoint(x: 6, y: 4.2), controlPoint1: NSPoint(x: 6.77, y: 6.5), controlPoint2: NSPoint(x: 6, y: 5.73))
        p.close()
        return p
    }

    private static let bubbleRect = NSRect(x: 6, y: 9, width: 12, height: 12)

    private static func ring() -> NSBezierPath {
        let p = NSBezierPath(ovalIn: bubbleRect)
        p.lineWidth = 2.2
        return p
    }

    private static func highlight() -> NSBezierPath {
        NSBezierPath(ovalIn: NSRect(x: 10 - 1.5, y: 13 - 1.5, width: 3, height: 3))
    }

    private static func stroke(_ points: [NSPoint], width: CGFloat) {
        guard let first = points.first else { return }
        let p = NSBezierPath()
        p.move(to: first)
        for pt in points.dropFirst() { p.line(to: pt) }
        p.lineWidth = width
        p.lineCapStyle = .round
        p.lineJoinStyle = .round
        p.stroke()
    }

    private func drawBubble() {
        switch self {
        case .peek:
            MenuFace.ring().stroke()
            MenuFace.highlight().fill()
        case .lookUp:
            MenuFace.ring().stroke()
            MenuFace.highlight().fill()
            // Garis "pop!" di kiri & kanan atas gelembung.
            MenuFace.stroke([NSPoint(x: 5.6, y: 9.9), NSPoint(x: 4.2, y: 8.5)], width: 2)
            MenuFace.stroke([NSPoint(x: 18.4, y: 9.9), NSPoint(x: 19.8, y: 8.5)], width: 2)
        case .wink:
            NSBezierPath(ovalIn: MenuFace.bubbleRect).fill()
        case .sleep:
            // Gelembung "kempis" jadi senyum tidur + z kecil.
            let smile = NSBezierPath()
            smile.move(to: NSPoint(x: 6.5, y: 16.5))
            smile.curve(to: NSPoint(x: 17.5, y: 16.5), controlPoint1: NSPoint(x: 10.17, y: 18.5), controlPoint2: NSPoint(x: 13.83, y: 18.5))
            smile.lineWidth = 2.2
            smile.lineCapStyle = .round
            smile.stroke()
            MenuFace.stroke([NSPoint(x: 15.5, y: 9.5), NSPoint(x: 18.5, y: 9.5),
                             NSPoint(x: 15.5, y: 12.5), NSPoint(x: 18.5, y: 12.5)], width: 1.6)
        case .focus:
            // Cincin progres: jejak samar + tiga perempat lingkaran.
            NSColor.black.withAlphaComponent(0.35).setStroke()
            MenuFace.ring().stroke()
            NSColor.black.setStroke()
            let arc = NSBezierPath()
            arc.appendArc(withCenter: NSPoint(x: 12, y: 15), radius: 6, startAngle: -90, endAngle: 180, clockwise: false)
            arc.lineWidth = 2.2
            arc.lineCapStyle = .round
            arc.stroke()
        }
    }
}
