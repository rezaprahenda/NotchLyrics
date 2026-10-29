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
        let leftCut: CGFloat = (mode == .compact && vm.hiddenEar == .left) ? vm.earWidth : 0
        let rightCut: CGFloat = (mode == .compact && vm.hiddenEar == .right) ? vm.earWidth : 0
        let shape = NotchShape(radius: radius, leftCut: leftCut, rightCut: rightCut)
        // Panel penuh & peek lebar memakai latar bergradasi; telinga tetap hitam pekat.
        let deep = mode == .expanded || (mode == .peek && vm.activePeek?.compact != true)

        // Saat kursor mendekati baris lirik (tembus klik), latar di bawah menu bar ikut memudar,
        // bukan hanya teksnya, supaya area di bawahnya terlihat jelas dan siap diklik.
        let lowerOpacity: Double = (mode == .compact && vm.lyricLineFaded) ? 0.12 : 1

        // Kaca butuh transparansi; Reduce Transparency → kembali ke Hidup.
        let style: PanelStyle = (vm.panelStyle == .glass && reduceTransparency) ? .vivid : vm.panelStyle

        // Kaca hanya untuk bagian yang turun di bawah menu bar.
        let showGlass = style == .glass && mode != .hidden && mode != .idle && size.height > vm.notchSize.height + 1

        ZStack(alignment: .top) {
            if showGlass {
                GlassBackdrop(radius: radius, alpha: lowerOpacity < 1 ? 0 : 1)
                    .padding(.leading, leftCut)
                    .padding(.trailing, rightCut)
                    .frame(width: size.width, height: size.height)
                    .allowsHitTesting(false)
            }
            notchBody(mode: mode, size: size, shape: shape, deep: deep, style: style,
                      showLine: showLine, lowerOpacity: lowerOpacity)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: mode)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: showLine)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: doubleLine)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: vm.hiddenEar)
        .frame(width: NotchViewModel.windowSize.width,
               height: NotchViewModel.windowSize.height,
               alignment: .top)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private func notchBody(mode: NotchMode, size: CGSize, shape: NotchShape, deep: Bool, style: PanelStyle,
                           showLine: Bool, lowerOpacity: Double) -> some View {
        ZStack(alignment: .top) {
            NotchFill(style: style, deep: deep, notchHeight: vm.notchSize.height, totalHeight: size.height)
                .clipShape(shape)
                .overlay {
                    if deep && style != .plain {
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
