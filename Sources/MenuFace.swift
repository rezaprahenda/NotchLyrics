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
    /// Digambar dalam grid 24×24 dengan sumbu y ke bawah, sama seperti desain SVG-nya.
    var image: NSImage {
        let face = self
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            let scale = NSAffineTransform()
            scale.scale(by: 18.0 / 24.0)
            scale.concat()
            NSColor.black.setFill()
            NSColor.black.setStroke()
            MenuFace.fringe().fill()
            face.drawFeatures()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = accessibilityLabel
        return image
    }

    /// Poni: tiga lengkung sama lebar.
    private static func fringe() -> NSBezierPath {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: 3, y: 2))
        p.line(to: NSPoint(x: 21, y: 2))
        p.line(to: NSPoint(x: 21, y: 7))
        p.curve(to: NSPoint(x: 18, y: 13), controlPoint1: NSPoint(x: 21, y: 10.3), controlPoint2: NSPoint(x: 19.6, y: 13))
        p.curve(to: NSPoint(x: 15, y: 11), controlPoint1: NSPoint(x: 16.6, y: 13), controlPoint2: NSPoint(x: 15.6, y: 12))
        p.curve(to: NSPoint(x: 12, y: 13), controlPoint1: NSPoint(x: 14.4, y: 12), controlPoint2: NSPoint(x: 13.4, y: 13))
        p.curve(to: NSPoint(x: 9, y: 11), controlPoint1: NSPoint(x: 10.6, y: 13), controlPoint2: NSPoint(x: 9.6, y: 12))
        p.curve(to: NSPoint(x: 6, y: 13), controlPoint1: NSPoint(x: 8.4, y: 12), controlPoint2: NSPoint(x: 7.4, y: 13))
        p.curve(to: NSPoint(x: 3, y: 7), controlPoint1: NSPoint(x: 4.4, y: 13), controlPoint2: NSPoint(x: 3, y: 10.3))
        p.close()
        return p
    }

    private func eye(_ x: CGFloat) -> NSBezierPath {
        NSBezierPath(ovalIn: NSRect(x: x - 1.6, y: 17.5 - 2.2, width: 3.2, height: 4.4))
    }

    /// Lengkung mata tertutup / kedip, melengkung ke bawah seperti "◡".
    private func closedEye(_ x: CGFloat) -> NSBezierPath {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: x - 2, y: 17))
        p.curve(to: NSPoint(x: x + 2, y: 17), controlPoint1: NSPoint(x: x - 1.2, y: 18.3), controlPoint2: NSPoint(x: x + 1.2, y: 18.3))
        p.lineWidth = 1.6
        p.lineCapStyle = .round
        return p
    }

    private func drawFeatures() {
        switch self {
        case .peek:
            eye(9).fill()
            eye(15).fill()
        case .lookUp:
            for x in [CGFloat(8.5), 15.5] {
                let ring = NSBezierPath(ovalIn: NSRect(x: x - 3, y: 15, width: 6, height: 6))
                ring.lineWidth = 1.5
                ring.stroke()
                NSBezierPath(ovalIn: NSRect(x: x + 0.5 - 1.3, y: 16.6 - 1.3, width: 2.6, height: 2.6)).fill()
            }
        case .wink:
            eye(9).fill()
            let p = NSBezierPath()
            p.move(to: NSPoint(x: 13, y: 18))
            p.curve(to: NSPoint(x: 17, y: 18), controlPoint1: NSPoint(x: 13.8, y: 16.4), controlPoint2: NSPoint(x: 16.2, y: 16.4))
            p.lineWidth = 1.6
            p.lineCapStyle = .round
            p.stroke()
        case .sleep:
            closedEye(8.3).stroke()
            closedEye(15.7).stroke()
        case .focus:
            for x in [CGFloat(9), 15] {
                let p = NSBezierPath()
                p.move(to: NSPoint(x: x - 1.8, y: 17.5))
                p.line(to: NSPoint(x: x + 1.8, y: 17.5))
                p.lineWidth = 1.8
                p.lineCapStyle = .round
                p.stroke()
            }
        }
    }
}
