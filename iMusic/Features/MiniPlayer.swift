import SwiftUI
import UIKit

struct MiniPlayer: View {
    let onOpen: () -> Void

    @EnvironmentObject private var player: PlayerModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if let song = player.current {
            HStack(spacing: 12) {
                ArtworkView(url: song.thumbnail, cornerRadius: 6)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 1) {
                    Text(song.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(song.artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Button { player.toggle() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(player.isPlaying ? "Jeda" : "Putar")
                Button { player.next(auto: false) } label: {
                    Image(systemName: "forward.fill")
                        .font(.body)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Berikutnya")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
            .shadow(radius: 8, y: 2)
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
            .accessibilityAction(named: "Buka pemutar") { onOpen() }
        }
    }
}
