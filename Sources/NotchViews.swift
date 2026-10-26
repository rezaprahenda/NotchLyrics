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

/// Bentuk notch: atas rata, sudut bawah membulat. Telinga kiri/kanan bisa "dipotong"
/// (selebar `leftCut` / `rightCut`, setinggi `cutHeight`) supaya menu bar di bawahnya terlihat.
struct NotchShape: Shape {
    var radius: CGFloat
    var leftCut: CGFloat = 0
    var rightCut: CGFloat = 0
    var cutHeight: CGFloat = 0

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(radius, AnimatablePair(leftCut, rightCut)) }
        set {
            radius = newValue.first
            leftCut = newValue.second.first
            rightCut = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = UnevenRoundedRectangle(topLeadingRadius: 0,
                                          bottomLeadingRadius: radius,
                                          bottomTrailingRadius: radius,
                                          topTrailingRadius: 0,
                                          style: .continuous)
            .path(in: rect)
        guard cutHeight > 0 else { return path }
        // Potongan dilebarkan ke atas & ke luar supaya hanya sudut dalamnya yang membulat.
        let r: CGFloat = 6
        if leftCut > 0.5 {
            let cut = CGRect(x: rect.minX - r, y: rect.minY - r, width: leftCut + r, height: cutHeight + r)
            path = path.subtracting(RoundedRectangle(cornerRadius: r, style: .continuous).path(in: cut))
        }
        if rightCut > 0.5 {
            let cut = CGRect(x: rect.maxX - rightCut, y: rect.minY - r, width: rightCut + r, height: cutHeight + r)
            path = path.subtracting(RoundedRectangle(cornerRadius: r, style: .continuous).path(in: cut))
        }
        return path
    }
}

// MARK: - Root

struct NotchRootView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var player: PlayerMonitor
    @ObservedObject var lyrics: LyricsStore

    var body: some View {
        let mode = vm.mode(hasTrack: player.track != nil)
        let showLine = vm.showsLyricLine(lyrics.state)
        let doubleLine = lyrics.compactIsDouble
        let size = vm.size(for: mode, showsLyricLine: showLine, doubleLine: doubleLine)
        let radius = vm.cornerRadius(for: mode)
        let leftCut: CGFloat = (mode == .compact && vm.hiddenEar == .left) ? vm.earWidth : 0
        let rightCut: CGFloat = (mode == .compact && vm.hiddenEar == .right) ? vm.earWidth : 0
        let shape = NotchShape(radius: radius, leftCut: leftCut, rightCut: rightCut,
                               cutHeight: vm.notchSize.height)

        // Saat kursor mendekati baris lirik (tembus klik), latar di bawah menu bar ikut memudar,
        // bukan hanya teksnya, supaya area di bawahnya terlihat jelas dan siap diklik.
        let lowerOpacity: Double = (mode == .compact && vm.lyricLineFaded) ? 0.12 : 1

        ZStack(alignment: .top) {
            shape
                .fill(Color.black)
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
                ExpandedView(vm: vm, player: player, lyrics: lyrics)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            case .compact:
                CompactView(vm: vm, player: player, lyrics: lyrics, showLine: showLine)
                    .transition(.opacity)
            case .peek:
                PeekView(vm: vm, player: player)
                    .transition(.opacity)
            case .idle, .hidden:
                EmptyView()
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .shadow(color: .black.opacity(mode == .expanded ? 0.35 : 0), radius: 12, y: 4)
        .opacity(mode == .hidden ? 0 : 1)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: mode)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: showLine)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: doubleLine)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: vm.hiddenEar)
        .frame(width: NotchViewModel.windowSize.width,
               height: NotchViewModel.windowSize.height,
               alignment: .top)
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Compact

struct CompactView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var player: PlayerMonitor
    @ObservedObject var lyrics: LyricsStore
    let showLine: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ArtworkView(image: player.artwork, size: 20, corner: 5)
                Spacer(minLength: vm.baseWidth)
                EqualizerView(isPlaying: player.isPlaying,
                              color: player.track?.source.tint ?? .white)
                    .frame(width: 20, height: 14)
            }
            .padding(.horizontal, 14)
            .frame(height: vm.notchSize.height)

            if showLine, let lines = lyrics.state.syncedLines {
                // Berhenti berdetak saat musik di-pause, supaya tidak memakan CPU.
                TimelineView(.animation(minimumInterval: 0.1, paused: !player.isPlaying)) { _ in
                    let idx = lyrics.currentIndex(in: lines, position: player.position)
                    let original = idx.map { lines[$0].text } ?? ""
                    let texts: (primary: String, secondary: String?) = idx.map {
                        lyrics.compactText(id: lines[$0].id, original: original)
                    } ?? (primary: original, secondary: nil)
                    ZStack {
                        VStack(spacing: 1) {
                            Text(texts.primary.isEmpty ? "♪" : texts.primary)
                                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.92))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            if let secondary = texts.secondary {
                                Text(secondary.isEmpty ? " " : secondary)
                                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.55))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                        }
                        .id(idx ?? -1)
                        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                                removal: .opacity))
                    }
                    .animation(.easeOut(duration: 0.25), value: idx)
                }
                .padding(.horizontal, 16)
                .frame(height: (lyrics.compactIsDouble ? vm.compactDoubleLyricHeight : vm.compactLyricHeight) - 4)
                .clipped()
                .opacity(vm.lyricLineSuppressed ? 0 : (vm.lyricLineFaded ? 0.15 : 1))
            }
        }
    }
}

// MARK: - Peek (ganti lagu)

struct PeekView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var player: PlayerMonitor

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: vm.notchSize.height)
            if let track = player.track {
                HStack(spacing: 10) {
                    ArtworkView(image: player.artwork, size: 34, corner: 7)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(track.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(track.artist)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    EqualizerView(isPlaying: player.isPlaying, color: track.source.tint)
                        .frame(width: 20, height: 14)
                }
                .padding(.horizontal, 16)
                .frame(height: vm.peekHeight - 4)
            }
        }
    }
}

// MARK: - Expanded

struct ExpandedView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var player: PlayerMonitor
    @ObservedObject var lyrics: LyricsStore

    var body: some View {
        VStack(spacing: 12) {
            Color.clear.frame(height: max(vm.notchSize.height - 6, 0))

            if let track = player.track {
                HStack(spacing: 12) {
                    ArtworkView(image: player.artwork, size: 50, corner: 10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                        Text(track.artist)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            Text(track.source.displayName)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(track.source.tint.opacity(0.9))
                            SleepIndicator(player: player)
                        }
                    }
                    Spacer(minLength: 8)
                    ControlsView(player: player)
                }

                LyricsPanel(player: player, lyrics: lyrics)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                HStack(spacing: 14) {
                    ProgressBar(player: player, duration: track.duration)
                    VolumeControl(player: player)
                }
            } else {
                EmptyStateView(permissionDenied: player.permissionDenied, error: player.lastError)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
        .foregroundStyle(.white)
    }
}

struct LyricsPanel: View {
    @ObservedObject var player: PlayerMonitor
    @ObservedObject var lyrics: LyricsStore

    var body: some View {
        if lyrics.isPickerOpen {
            LyricsPickerView(lyrics: lyrics, trackDuration: player.track?.duration ?? 0)
        } else {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch lyrics.state {
        case .synced(let lines):
            SyncedLyricsView(lines: lines, player: player, lyrics: lyrics)
                .overlay(alignment: .topTrailing) {
                    LyricsToolbar(lyrics: lyrics, showOffset: true)
                }
                .overlay(alignment: .bottom) {
                    TranslationErrorNote(lyrics: lyrics)
                }
        case .plain(let lines):
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Lirik tidak tersinkron", "Lyrics not synced"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                    ForEach(Array(lines.enumerated()), id: \.offset) { item in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.element)
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.8))
                            if lyrics.romanizationEnabled, let latin = lyrics.romanized[item.offset] {
                                Text(latin)
                                    .font(.system(size: 12, weight: .medium))
                                    .italic()
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                            if lyrics.translationEnabled, let translated = lyrics.translations[item.offset] {
                                Text(translated)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.white.opacity(0.45))
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .overlay(alignment: .topTrailing) { LyricsToolbar(lyrics: lyrics, showOffset: false) }
            .overlay(alignment: .bottom) { TranslationErrorNote(lyrics: lyrics) }
        case .loading:
            message(L("Mencari lirik…", "Searching lyrics…"), withSearch: false)
        case .instrumental:
            message("♪ Instrumental", withSearch: true)
        case .notFound, .none:
            message(L("Lirik tidak tersedia untuk lagu ini", "No lyrics available for this song"), withSearch: true)
        }
    }

    private func message(_ s: String, withSearch: Bool) -> some View {
        VStack(spacing: 10) {
            Text(s)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.5))
            if withSearch {
                Button {
                    lyrics.isPickerOpen = true
                } label: {
                    Label(L("Cari lirik lain", "Find other lyrics"), systemImage: "magnifyingglass")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Deretan tombol kecil di pojok kanan atas lirik: Aa, ID, offset, pilih lirik.
struct LyricsToolbar: View {
    @ObservedObject var lyrics: LyricsStore
    let showOffset: Bool

    var body: some View {
        HStack(spacing: 6) {
            if lyrics.hasRomanization {
                PillToggle(label: "Aa", symbol: nil, isOn: lyrics.romanizationEnabled) {
                    lyrics.romanizationEnabled.toggle()
                }
                .help(L("Tampilkan huruf latin (romanisasi)", "Show romanization"))
            }
            if #available(macOS 15.0, *) {
                TranslateToggle(lyrics: lyrics)
            }
            if showOffset {
                OffsetControl(lyrics: lyrics)
            }
            PillToggle(label: nil, symbol: "text.magnifyingglass", isOn: lyrics.hasOverride) {
                lyrics.isPickerOpen = true
            }
            .help(L("Pilih lirik lain", "Choose other lyrics"))
        }
    }
}

/// Tombol kapsul kecil yang bisa menyala/mati.
struct PillToggle: View {
    let label: String?
    let symbol: String?
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                }
                if let label {
                    Text(label).font(.system(size: 10, weight: .bold))
                }
            }
            .foregroundStyle(.white.opacity(isOn ? 1 : 0.55))
            .padding(.horizontal, 7)
            .frame(minWidth: 24)
            .frame(height: 22)
            .background(Capsule().fill(Color.white.opacity(isOn ? 0.22 : 0.08)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Pilih lirik manual

struct LyricsPickerView: View {
    @ObservedObject var lyrics: LyricsStore
    let trackDuration: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(L("Pilih lirik", "Choose lyrics"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                if lyrics.hasOverride {
                    Button(L("Kembali ke otomatis", "Back to automatic")) { lyrics.resetToAutomatic() }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Button {
                    lyrics.isPickerOpen = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if lyrics.isSearchingCandidates {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if lyrics.candidates.isEmpty {
                Text(L("Tidak ada hasil lain di LRCLIB", "No other results on LRCLIB"))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(lyrics.candidates) { c in
                            CandidateRow(candidate: c, trackDuration: trackDuration) {
                                lyrics.choose(c)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct CandidateRow: View {
    let candidate: LyricCandidate
    let trackDuration: Double
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(candidate.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(candidate.album.isEmpty ? candidate.artist : "\(candidate.artist) · \(candidate.album)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                // Durasi hijau = cocok dengan lagu yang sedang diputar (selisih ≤ 2 detik).
                Text(format(candidate.duration))
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(durationMatches ? Color.green.opacity(0.85) : Color.white.opacity(0.45))
                Text(candidate.hasSynced ? L("Sinkron", "Synced") : (candidate.instrumental ? "Instrumental" : L("Teks", "Text")))
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(candidate.hasSynced ? 0.95 : 0.6))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(candidate.hasSynced ? 0.18 : 0.08)))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(hover ? 0.1 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }

    private var durationMatches: Bool {
        trackDuration > 0 && abs(candidate.duration - trackDuration) <= 2
    }

    private func format(_ t: Double) -> String {
        let s = Int(max(t, 0))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

struct SyncedLyricsView: View {
    let lines: [LyricLine]
    @ObservedObject var player: PlayerMonitor
    @ObservedObject var lyrics: LyricsStore
    @State private var current: Int = -1
    @State private var hovered: Int?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    Color.clear.frame(height: 30)
                    ForEach(lines) { line in
                        let isCurrent = line.id == current
                        let isHovered = line.id == hovered
                        // Klik baris lirik = lompat ke bagian lagu itu.
                        Button {
                            player.seek(to: line.time - lyrics.offset)
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(line.text.isEmpty ? "♪" : line.text)
                                    .font(.system(size: isCurrent ? 16 : 13.5,
                                                  weight: isCurrent ? .bold : .medium,
                                                  design: .rounded))
                                    .foregroundStyle(.white.opacity(isCurrent || isHovered ? 1 : (line.id < current ? 0.35 : 0.5)))
                                if lyrics.romanizationEnabled, let latin = lyrics.romanized[line.id] {
                                    Text(latin)
                                        .font(.system(size: isCurrent ? 13 : 12, weight: .medium, design: .rounded))
                                        .italic()
                                        .foregroundStyle(.white.opacity(isCurrent ? 0.85 : 0.4))
                                }
                                if lyrics.translationEnabled, let translated = lyrics.translations[line.id] {
                                    Text(translated)
                                        .font(.system(size: isCurrent ? 12.5 : 11.5, design: .rounded))
                                        .foregroundStyle(.white.opacity(isCurrent ? 0.7 : 0.3))
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .onHover { inside in
                            if inside {
                                hovered = line.id
                            } else if hovered == line.id {
                                hovered = nil
                            }
                        }
                        .id(line.id)
                    }
                    Color.clear.frame(height: 30)
                }
            }
            .mask(
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.18),
                    .init(color: .black, location: 0.82),
                    .init(color: .clear, location: 1),
                ], startPoint: .top, endPoint: .bottom)
            )
            .task(id: lines) {
                current = -1
                tick(proxy, animated: false)
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    tick(proxy, animated: true)
                }
            }
        }
    }

    private func tick(_ proxy: ScrollViewProxy, animated: Bool) {
        let idx = lyrics.currentIndex(in: lines, position: player.position) ?? -1
        guard idx != current else { return }
        if animated {
            withAnimation(.easeInOut(duration: 0.35)) {
                current = idx
                if idx >= 0 { proxy.scrollTo(idx, anchor: .center) }
            }
        } else {
            current = idx
            if idx >= 0 { proxy.scrollTo(idx, anchor: .center) }
        }
    }
}

// MARK: - Komponen kecil

/// Tombol − / + untuk menggeser waktu lirik. Klik angkanya untuk reset.
struct OffsetControl: View {
    @ObservedObject var lyrics: LyricsStore

    var body: some View {
        HStack(spacing: 2) {
            SmallIconButton(symbol: "minus") { lyrics.adjustOffset(by: -0.5) }
            Button {
                lyrics.resetOffset()
            } label: {
                Text(label)
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(lyrics.offset == 0 ? 0.45 : 0.95))
                    .frame(minWidth: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            SmallIconButton(symbol: "plus") { lyrics.adjustOffset(by: 0.5) }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.white.opacity(0.08)))
        .help(L("+ = lirik lebih cepat, − = lebih lambat. Klik angka untuk reset.", "+ = lyrics earlier, − = later. Click the number to reset."))
    }

    private var label: String {
        lyrics.offset == 0 ? "0.0s" : String(format: "%+.1fs", lyrics.offset)
    }
}

struct SmallIconButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ControlsView: View {
    @ObservedObject var player: PlayerMonitor

    var body: some View {
        HStack(spacing: 6) {
            // Tombol favorit hanya muncul untuk Apple Music.
            if let fav = player.isFavorite {
                ControlButton(symbol: fav ? "heart.fill" : "heart", size: 13,
                              tint: fav ? Color(red: 0.98, green: 0.24, blue: 0.35) : .white,
                              box: 26) {
                    player.toggleFavorite()
                }
            }
            if let shuffle = player.shuffle {
                ControlButton(symbol: "shuffle", size: 12,
                              tint: .white.opacity(shuffle ? 1 : 0.35), box: 26) {
                    player.toggleShuffle()
                }
            }
            ControlButton(symbol: "backward.fill", size: 14) { player.previous() }
            ControlButton(symbol: player.isPlaying ? "pause.fill" : "play.fill", size: 20) { player.playPause() }
            ControlButton(symbol: "forward.fill", size: 14) { player.next() }
            if let mode = player.repeatMode {
                ControlButton(symbol: mode == .one ? "repeat.1" : "repeat", size: 12,
                              tint: .white.opacity(mode == .off ? 0.35 : 1), box: 26) {
                    player.cycleRepeat()
                }
            }
        }
    }
}

struct ControlButton: View {
    let symbol: String
    let size: CGFloat
    var tint: Color = .white
    var box: CGFloat = 32
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: box, height: box)
                .background(Circle().fill(Color.white.opacity(hover ? 0.12 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Progress bar yang bisa diklik / di-drag untuk lompat ke bagian lagu.
struct ProgressBar: View {
    @ObservedObject var player: PlayerMonitor
    let duration: Double
    @State private var dragFraction: Double?
    @State private var hovering = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let pos = dragFraction.map { $0 * duration } ?? player.position
            let fraction = duration > 0 ? min(max(pos / duration, 0), 1) : 0
            let active = hovering || dragFraction != nil
            HStack(spacing: 8) {
                Text(format(pos)).monospacedDigit()
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.2))
                            .frame(height: active ? 6 : 4)
                        Capsule()
                            .fill(Color.white.opacity(active ? 1 : 0.85))
                            .frame(width: g.size.width * fraction, height: active ? 6 : 4)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                dragFraction = min(max(v.location.x / max(g.size.width, 1), 0), 1)
                            }
                            .onEnded { v in
                                let f = min(max(v.location.x / max(g.size.width, 1), 0), 1)
                                dragFraction = nil
                                if duration > 0 { player.seek(to: f * duration) }
                            }
                    )
                }
                .frame(height: 14)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.15), value: active)
                Text(format(duration)).monospacedDigit()
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white.opacity(0.6))
        }
        .frame(height: 16)
    }

    private func format(_ t: Double) -> String {
        let s = Int(max(t, 0))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// "🌙 23 mnt" di samping nama app saat sleep timer aktif.
struct SleepIndicator: View {
    @ObservedObject var player: PlayerMonitor

    var body: some View {
        if player.sleepAtTrackEnd || player.sleepUntil != nil {
            TimelineView(.periodic(from: .now, by: 15)) { ctx in
                HStack(spacing: 3) {
                    Image(systemName: "moon.fill").font(.system(size: 8))
                    Text(label(now: ctx.date)).font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    private func label(now: Date) -> String {
        if player.sleepAtTrackEnd { return L("akhir lagu", "end of song") }
        guard let until = player.sleepUntil else { return "" }
        let minutes = max(1, Int((until.timeIntervalSince(now) / 60).rounded(.up)))
        return L("\(minutes) mnt", "\(minutes) min")
    }
}

/// Volume app musik (Spotify/Music), bukan volume sistem.
struct VolumeControl: View {
    @ObservedObject var player: PlayerMonitor

    var body: some View {
        if let v = player.volume {
            HStack(spacing: 4) {
                Image(systemName: v < 1 ? "speaker.slash.fill" : (v < 50 ? "speaker.wave.1.fill" : "speaker.wave.2.fill"))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 16)
                Slider(value: Binding(get: { player.volume ?? 0 },
                                      set: { player.setVolume($0) }),
                       in: 0...100)
                    .controlSize(.mini)
                    .tint(.white)
            }
            .frame(width: 96)
        }
    }
}

struct ArtworkView: View {
    let image: NSImage?
    let size: CGFloat
    let corner: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.white.opacity(0.12)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.45))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

struct EqualizerView: View {
    let isPlaying: Bool
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isPlaying)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2.5) {
                ForEach(0..<4, id: \.self) { i in
                    let phase = t * (4.2 + Double(i) * 1.3) + Double(i) * 1.7
                    let h = isPlaying ? 0.35 + 0.65 * abs(sin(phase)) : 0.25
                    Capsule()
                        .fill(color.opacity(0.9))
                        .frame(width: 2.6, height: 14 * h)
                }
            }
            .frame(height: 14)
        }
    }
}

struct EmptyStateView: View {
    let permissionDenied: MusicSource?
    let error: String?

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: permissionDenied == nil ? "music.note" : "lock.fill")
                .font(.system(size: 22))
                .foregroundStyle(.white.opacity(0.6))
            if let src = permissionDenied {
                Text(L("Izin dibutuhkan untuk membaca \(src.displayName)", "Permission needed to read \(src.displayName)"))
                    .font(.system(size: 13, weight: .semibold))
                Text(L("Buka System Settings › Privacy & Security › Automation, lalu aktifkan \(src.displayName) untuk NotchLyrics.", "Open System Settings › Privacy & Security › Automation and enable \(src.displayName) for NotchLyrics."))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            } else {
                Text(L("Tidak ada musik yang diputar", "Nothing playing"))
                    .font(.system(size: 13, weight: .semibold))
                Text(L("Putar lagu di Spotify atau Apple Music", "Play a song in Spotify or Apple Music"))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
            }
            if let error, permissionDenied == nil {
                Text(error)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.orange.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .textSelection(.enabled)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
