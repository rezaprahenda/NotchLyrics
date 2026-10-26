import AppKit

extension NSImage {
    /// Warna aksen dari cover album: rata-rata piksel yang paling "berwarna" (jenuh & terang),
    /// lalu dicerahkan supaya tetap terbaca di atas latar hitam notch.
    func accentColor() -> NSColor? {
        let side = 24
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: side * 4, bitsPerPixel: 32)
        else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw(in: NSRect(x: 0, y: 0, width: side, height: side),
             from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        var samples: [(score: CGFloat, color: NSColor)] = []
        samples.reserveCapacity(side * side)
        for x in 0..<side {
            for y in 0..<side {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
                samples.append((s * 0.7 + b * 0.3, c))
            }
        }
        guard !samples.isEmpty else { return nil }

        // Ambil 20% piksel dengan skor tertinggi, rata-ratakan.
        let top = samples.sorted { $0.score > $1.score }.prefix(max(1, samples.count / 5))
        var r: CGFloat = 0, g: CGFloat = 0, bl: CGFloat = 0
        for item in top {
            r += item.color.redComponent
            g += item.color.greenComponent
            bl += item.color.blueComponent
        }
        let n = CGFloat(top.count)
        let avg = NSColor(deviceRed: r / n, green: g / n, blue: bl / n, alpha: 1)

        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        avg.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        // Cover hampir abu-abu → tidak ada warna yang layak; pakai warna app saja.
        guard s > 0.15 else { return nil }
        return NSColor(deviceHue: h, saturation: min(s, 0.85), brightness: max(b, 0.75), alpha: 1)
    }
}
