import SwiftUI
import AppKit

extension MusicSource {
    var tint: Color {
        switch self {
        case .spotify: return Color(red: 0.12, green: 0.84, blue: 0.38)
        case .music: return Color(red: 0.98, green: 0.24, blue: 0.35)
        }
    }
}

/// Bentuk notch: atas rata, sudut bawah membulat. Sisi kiri/kanan bisa disembunyikan penuh
/// (selebar `leftCut` / `rightCut`) supaya menu bar app di bawahnya terlihat dan bisa diklik.
struct NotchShape: Shape {
    var radius: CGFloat
    var leftCut: CGFloat = 0
    var rightCut: CGFloat = 0

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(radius, AnimatablePair(leftCut, rightCut)) }
        set {
            radius = newValue.first
            leftCut = newValue.second.first
            rightCut = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let r = CGRect(x: rect.minX + leftCut, y: rect.minY,
                       width: max(rect.width - leftCut - rightCut, 0), height: rect.height)
        return UnevenRoundedRectangle(topLeadingRadius: 0,
                                      bottomLeadingRadius: radius,
                                      bottomTrailingRadius: radius,
                                      topTrailingRadius: 0,
                                      style: .continuous)
            .path(in: r)
    }
}

// MARK: - Root

struct NotchRootView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var player: PlayerMonitor
    @ObservedObject var lyrics: LyricsStore
    @ObservedObject var pomodoro: PomodoroModule
    @ObservedObject var prayer: PrayerModule
    @ObservedObject var shelf: ShelfModule
    let mirror: MirrorModule
    let clipboard: ClipboardModule
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let mode = vm.mode()
        let showLine = vm.showsLyricLine(lyrics.state)
        let doubleLine = lyrics.compactIsDouble
        let size = vm.size(for: mode, showsLyricLine: showLine, doubleLine: doubleLine)
        let radius = vm.cornerRadius(for: mode)
        // Telinga musik yang disingkirkan memudar (lihat earMask), bukan dipotong.
        let cutEars = mode == .compact && !vm.earsAreControls
        let leftCut: CGFloat = (cutEars && vm.hiddenEar == .left) ? vm.earWidth : 0
        let rightCut: CGFloat = (cutEars && vm.hiddenEar == .right) ? vm.earWidth : 0
        let shape = NotchShape(radius: radius, leftCut: leftCut, rightCut: rightCut)
        // Panel penuh & peek lebar memakai latar bergradasi; telinga tetap hitam pekat.
        let deep = mode == .expanded || (mode == .peek && vm.activePeek?.compact != true)

        // Saat kursor mendekati baris lirik (tembus klik), latar di bawah menu bar ikut memudar,
        // bukan hanya teksnya, supaya area di bawahnya terlihat jelas dan siap diklik.
        let lowerOpacity: Double = (mode == .compact && vm.lyricLineFaded) ? 0.12 : 1

        // Kaca butuh transparansi; Reduce Transparency → kembali ke Hidup.
        let style: PanelStyle = (vm.panelStyle == .glass && reduceTransparency) ? .vivid : vm.panelStyle

        // Kacanya sendiri (gaya Kaca) dipasang NotchController di bawah tampilan ini.
        ZStack(alignment: .top) {
            notchBody(mode: mode, size: size, shape: shape, deep: deep, style: style,
                      showLine: showLine, lowerOpacity: lowerOpacity)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: mode)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: showLine)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: doubleLine)
        .animation(vm.earsAreControls ? .easeOut(duration: 0.2) : .spring(response: 0.3, dampingFraction: 0.85),
                   value: vm.hiddenEar)
        .frame(width: NotchViewModel.windowSize.width,
               height: NotchViewModel.windowSize.height,
               alignment: .top)
        .environment(\.colorScheme, .dark)
    }

    /// Masker satu kolom telinga: pekat biasa · ditunjuk = gradasi dari tepi notch ke luar ·
    /// disingkirkan = pudar rata seperti baris lirik. Dibuat dari lapisan opacity supaya transisinya halus.
    @ViewBuilder
    private func earMask(_ side: EarSide, mode: NotchMode) -> some View {
        let active = mode == .compact && vm.earsAreControls
        let hidden = active && vm.hiddenEar == side
        let hovered = active && !hidden && vm.hoveredEar == side
        ZStack {
            Rectangle().opacity(hidden || hovered ? 0 : 1)
            LinearGradient(colors: side == .left ? [.black.opacity(0.25), .black] : [.black, .black.opacity(0.25)],
                           startPoint: .leading, endPoint: .trailing)
                .opacity(hovered ? 1 : 0)
            Rectangle().opacity(hidden ? 0.12 : 0)
        }
        .frame(width: mode == .compact ? vm.earWidth : 0)
    }

    /// Bagian tengah (di bawah notch). Saat telinga musik disingkirkan, sudut bawahnya di sisi itu
    /// ikut membulat, jadi yang tersisa tampak seperti panel utuh + "bayangan" telinga yang memudar.
    private func middleMask(mode: NotchMode, radius: CGFloat) -> some View {
        let active = mode == .compact && vm.earsAreControls
        let left = active && vm.hiddenEar == .left
        let right = active && vm.hiddenEar == .right
        return ZStack {
            Rectangle().opacity(left || right ? 0.12 : 0)
            UnevenRoundedRectangle(topLeadingRadius: 0,
                                   bottomLeadingRadius: left ? radius : 0,
                                   bottomTrailingRadius: right ? radius : 0,
                                   topTrailingRadius: 0,
                                   style: .continuous)
        }
    }

    @ViewBuilder
    private func notchBody(mode: NotchMode, size: CGSize, shape: NotchShape, deep: Bool, style: PanelStyle,
                           showLine: Bool, lowerOpacity: Double) -> some View {
        ZStack(alignment: .top) {
            NotchFill(style: style, deep: deep, notchHeight: vm.notchSize.height, totalHeight: size.height,
                      glassDarkness: vm.glassDarkness)
                .clipShape(shape)
                .overlay {
                    if deep && style == .glass {
                        // Kaca di atas latar putih: garis tepi gelap tipis supaya bentuk panel tetap terbaca.
                        shape.stroke(LinearGradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .clear, location: 0.45),
                            .init(color: .black.opacity(0.22), location: 1),
                        ], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                    }
                    if deep && style == .vivid {
                        // Garis terang tipis hanya di tepi bawah, supaya bentuk panel terbaca di wallpaper gelap.
                        shape.stroke(LinearGradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .clear, location: 0.7),
                            .init(color: .white.opacity(0.09), location: 1),
                        ], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                    }
                }
                .mask(alignment: .top) {
                    // Gradasi halus dari pekat (menu bar) ke transparan (baris lirik), tanpa garis potong.
                    VStack(spacing: 0) {
                        Rectangle()
                            .frame(height: vm.notchSize.height) // area notch fisik tetap pekat
                        // Gradasi membentang di seluruh area baris lirik; memudar lebih cepat di awal.
                        LinearGradient(stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black.opacity(lowerOpacity + (1 - lowerOpacity) * 0.35), location: 0.3),
                            .init(color: .black.opacity(lowerOpacity), location: 1),
                        ], startPoint: .top, endPoint: .bottom)
                    }
                }
                .mask(alignment: .top) {
                    // Telinga musik yang ditunjuk kursor: seluruh kolom sisi itu (telinga + baris
                    // lirik di bawahnya) memudar dengan gradasi yang mulai di tepi notch dan makin
                    // pudar ke luar, supaya menu bar di baliknya terlihat. Isinya jadi tombol (CompactView).
                    HStack(spacing: 0) {
                        earMask(.left, mode: mode)
                        middleMask(mode: mode, radius: shape.radius)
                        earMask(.right, mode: mode)
                    }
                }

            // Mesin terjemahan (tak terlihat), selalu terpasang supaya terjemahan siap sebelum hover.
            if #available(macOS 15.0, *) {
                TranslationRunner(lyrics: lyrics)
            }

            switch mode {
            case .expanded:
                ExpandedView(vm: vm, player: player, lyrics: lyrics, pomodoro: pomodoro, prayer: prayer, shelf: shelf,
                             mirror: mirror, clipboard: clipboard)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            case .compact:
                CompactView(vm: vm, player: player, lyrics: lyrics, pomodoro: pomodoro, prayer: prayer, shelf: shelf, showLine: showLine)
                    .transition(.opacity)
            case .peek:
                PeekView(vm: vm, player: player, pomodoro: pomodoro, prayer: prayer)
                    .transition(.opacity)
            case .idle, .hidden:
                EmptyView()
            }
        }
        .frame(width: size.width, height: size.height)
        .environment(\.panelStyle, style)
        .clipShape(shape)
        // Bayangan di bawah kaca akan menggelapkan kacanya, jadi gaya Kaca tanpa bayangan SwiftUI.
        .shadow(color: .black.opacity(mode == .expanded && style != .glass ? 0.35 : 0), radius: 12, y: 4)
        .opacity(mode == .hidden ? 0 : 1)
    }
}
