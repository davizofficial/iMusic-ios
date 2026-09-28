import SwiftUI

struct DownloadsView: View {
    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var player: PlayerModel

    var body: some View {
        Group {
            if downloads.tracks.isEmpty {
                EmptyStateView(title: "Belum ada unduhan",
                               message: "Unduh lagu atau seluruh playlist lewat menu panjang pada lagu.",
                               systemImage: "arrow.down.circle")
            } else {
                List {
                    if downloads.isBatchRunning {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Mengunduh \(downloads.batchDone)/\(downloads.batchTotal)…")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    ForEach(downloads.tracks) { track in
                        Button {
                            player.play(track.song, queue: downloads.tracks.map(\.song))
                        } label: {
                            HStack(spacing: 12) {
                                ArtworkView(url: track.thumbnail, cornerRadius: 4)
                                    .frame(width: 44, height: 44)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(track.title)
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(1)
                                    Text(track.artist)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 4)
                                Text(track.format.uppercased())
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { indexSet in
                        for i in indexSet { downloads.delete(downloads.tracks[i].videoId) }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Unduhan")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Unduhan", isPresented: Binding(
            get: { downloads.lastError != nil },
            set: { if !$0 { downloads.lastError = nil } }
        )) {
            Button("OK") { downloads.lastError = nil }
        } message: {
            Text(downloads.lastError ?? "")
        }
    }
}
