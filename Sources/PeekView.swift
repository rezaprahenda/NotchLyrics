import SwiftUI
import AppKit

// MARK: - Peek (kejadian singkat)

struct PeekView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var player: PlayerMonitor
    @ObservedObject var pomodoro: PomodoroModule
    @ObservedObject var prayer: PrayerModule

    var body: some View {
        if let peek = vm.activePeek, peek.compact {
            compactRow(peek)
        } else {
            fullBody
        }
    }

    /// Peek ringkas: isi hanya di telinga kiri & kanan, notch tidak melebar.
    private func compactRow(_ peek: PeekEvent) -> some View {
        HStack(spacing: 0) {
            Group {
                if let level = peek.level {
                    BatteryGlyph(level: level, charging: peek.symbol == "bolt")
                } else {
                    Image(systemName: peek.symbol.isEmpty ? symbol(for: peek) : peek.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tint(for: peek))
                }
            }
            .frame(width: 26, alignment: .leading)
            Spacer(minLength: vm.baseWidth)
            Text(peek.title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(BatteryGlyph.color(level: peek.level ?? 1, charging: peek.symbol == "bolt"))
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 14)
        .frame(height: vm.notchSize.height)
    }

    private var fullBody: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: vm.notchSize.height)
            if let peek = vm.activePeek {
                Group {
                    if peek.kind == .trackChange {
                        trackRow
                    } else {
                        eventRow(peek)
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: vm.peekHeight - 4)
            }
        }
    }

    @ViewBuilder private var trackRow: some View {
        HStack(spacing: 10) {
            ArtworkView(image: player.artwork, size: 34, corner: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(player.track?.title ?? vm.activePeek?.title ?? "")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(player.track?.artist ?? vm.activePeek?.subtitle ?? "")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            EqualizerView(isPlaying: player.isPlaying, color: vm.accent(for: player))
                .frame(width: 20, height: 14)
        }
    }

    private func eventRow(_ peek: PeekEvent) -> some View {
        HStack(spacing: 12) {
            Image(systemName: peek.symbol.isEmpty ? symbol(for: peek) : peek.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint(for: peek))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(peek.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if !peek.subtitle.isEmpty {
                    Text(peek.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            if peek.kind == .pomodoro, pomodoro.waitingFor != nil {
                PeekButton(title: L("Mulai", "Start"), filled: true, tint: tint(for: peek)) {
                    pomodoro.acceptNext()
                    vm.dismissPeek?()
                }
                PeekButton(title: L("Lewati", "Skip"), filled: false, tint: tint(for: peek)) {
                    pomodoro.skipNext()
                    vm.dismissPeek?()
                }
            }
            if peek.kind == .prayer, prayer.adhanSound != .off {
                PeekButton(title: L("Matikan suara", "Mute"), filled: true, tint: tint(for: peek)) {
                    prayer.stopAdhan()
                    vm.dismissPeek?()
                }
            }
        }
    }

    private func symbol(for peek: PeekEvent) -> String {
        switch peek.kind {
        case .pomodoro: return "timer"
        case .reminder: return "bell"
        case .device: return "battery.75percent"
        case .prayer: return "moon.stars"
        case .trackChange: return "music.note"
        }
    }

    private func tint(for peek: PeekEvent) -> Color {
        switch peek.kind {
        case .pomodoro: return pomodoro.waitingFor?.isBreak == true ? .breakAccent : .focusAccent
        case .reminder: return .reminderAccent
        case .device: return .deviceAccent
        case .prayer: return .prayerAccent
        case .trackChange: return vm.accent(for: player)
        }
    }
}

/// Tombol kapsul kecil di dalam peek.
struct PeekButton: View {
    let title: String
    let filled: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(filled ? Color.black.opacity(0.85) : .white)
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background {
                    if filled {
                        Capsule()
                            .fill(LinearGradient(colors: [tint.lighter(0.22), tint],
                                                 startPoint: .top, endPoint: .bottom))
                            .overlay(Capsule().strokeBorder(
                                LinearGradient(colors: [.white.opacity(0.35), .clear],
                                               startPoint: .top, endPoint: .center), lineWidth: 1))
                            .softGlow(tint, radius: 5)
                    } else {
                        Capsule()
                            .fill(Color.white.opacity(0.13))
                            .overlay(Capsule().strokeBorder(
                                LinearGradient(colors: [.white.opacity(0.10), .clear],
                                               startPoint: .top, endPoint: .center), lineWidth: 1))
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
