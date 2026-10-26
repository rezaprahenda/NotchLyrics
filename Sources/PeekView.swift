import SwiftUI
import AppKit

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
                    EqualizerView(isPlaying: player.isPlaying, color: vm.accent(for: player))
                        .frame(width: 20, height: 14)
                }
                .padding(.horizontal, 16)
                .frame(height: vm.peekHeight - 4)
            }
        }
    }
}
