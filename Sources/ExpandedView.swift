import SwiftUI
import AppKit

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
                                .foregroundStyle(vm.accent(for: player).opacity(0.9))
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
                PillToggle(label: nil, symbol: "music.mic", isOn: lyrics.karaokeEnabled) {
                    lyrics.karaokeEnabled.toggle()
                }
                .help(L("Karaoke: baris terisi mengikuti lagu", "Karaoke: fill lines as they are sung"))
                OffsetControl(lyrics: lyrics)
            }
            PillToggle(label: nil, symbol: "text.magnifyingglass", isOn: lyrics.hasOverride) {
                lyrics.isPickerOpen = true
            }
            .help(L("Pilih lirik lain", "Choose other lyrics"))
        }
    }
}

/// Teks yang terisi dari kiri ke kanan sesuai `progress` (0…1). `progress` nil = teks biasa.
struct KaraokeText: View {
    let text: String
    let progress: Double?
    let font: Font
    let color: Color

    var body: some View {
        if let progress {
            Text(text)
                .font(font)
                .foregroundStyle(color.opacity(0.4))
                .overlay(alignment: .leading) {
                    Text(text)
                        .font(font)
                        .foregroundStyle(color)
                        .mask(alignment: .leading) {
                            GeometryReader { g in
                                Rectangle().frame(width: g.size.width * min(max(progress, 0), 1))
                            }
                        }
                }
        } else {
            Text(text)
                .font(font)
                .foregroundStyle(color)
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
