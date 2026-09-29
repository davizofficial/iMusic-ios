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
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                VStack(alignment: .leading, spacing: 2) {
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
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(player.isPlaying ? "Jeda" : "Putar")
                Button { player.next(auto: false) } label: {
                    Image(systemName: "forward.fill")
                        .font(.body)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Berikutnya")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
            .accessibilityAction(named: "Buka pemutar") { onOpen() }
        }
    }
}
