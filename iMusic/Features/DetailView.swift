import SwiftUI

struct DetailView: View {
    let browseId: String
    let kind: String
    var params: String? = nil

    @EnvironmentObject private var player: PlayerModel
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var downloads: DownloadManager
    @State private var page: BrowsePage?
    @State private var state: LoadState = .loading

    private var header: PageHeader? { page?.header }
    private var tracks: [MediaItem] { page?.tracks ?? [] }

    private var kicker: String {
        switch kind {
        case "artist": return "Artis"
        case "album": return "Album"
        case "playlist": return "Playlist"
        default: return "Koleksi"
        }
    }

    var body: some View {
        Group {
            switch state {
            case .loading:
                LoadingView()
            case .failed(let message):
                ErrorStateView(message: message) { Task { await load() } }
            case .loaded:
                content
            }
        }
        .navigationTitle(header?.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task { if page == nil { await load() } }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let header { headerView(header) }
                if !tracks.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(tracks.enumerated()), id: \.offset) { idx, item in
                            SongRow(item: item, number: idx + 1, queue: tracks)
                        }
                    }
                }
                ForEach(Array((page?.sections ?? []).enumerated()), id: \.offset) { _, section in
                    ShelfView(section: section)
                }
            }
            .padding(.bottom, 24)
        }
        .refreshable { await load() }
    }

    private func headerView(_ header: PageHeader) -> some View {
        HStack(alignment: .bottom, spacing: 16) {
            ArtworkView(url: header.thumbnail, cornerRadius: kind == "artist" ? 90 : 10)
                .frame(width: 160, height: 160)
                .shadow(radius: 12, y: 6)
            VStack(alignment: .leading, spacing: 6) {
                Text(kicker)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(header.title)
                    .font(.title2.bold())
                    .lineLimit(3)
                if let sub = header.subtitle ?? header.strapline, !sub.isEmpty {
                    Text(sub)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 10) {
                    if !tracks.isEmpty {
                        Button {
                            player.playItems(tracks)
                        } label: {
                            Label("Putar", systemImage: "play.fill")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)

                        Button {
                            player.playItems(tracks.shuffled())
                        } label: {
                            Image(systemName: "shuffle")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Acak")
                    }
                    Button {
                        library.toggleSaved(headerItem(header))
                    } label: {
                        Image(systemName: library.isSaved(browseId) ? "bookmark.fill" : "bookmark")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(library.isSaved(browseId) ? "Hapus dari tersimpan" : "Simpan")

                    if !tracks.isEmpty {
                        Button {
                            Task {
                                await downloads.downloadPlaylist(tracks.map(\.song),
                                                                  format: library.settings.downloadFormat)
                            }
                        } label: {
                            Image(systemName: "arrow.down.circle")
                        }
                        .buttonStyle(.bordered)
                        .disabled(downloads.isBatchRunning)
                        .accessibilityLabel("Unduh semua")
                    }
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.top, 8)
    }

    private func headerItem(_ header: PageHeader) -> MediaItem {
        MediaItem(type: kind == "artist" ? "artist" : (kind == "album" ? "album" : "playlist"),
                  title: header.title,
                  subtitle: header.subtitle,
                  thumbnail: header.thumbnail,
                  browseId: browseId,
                  browseType: kind,
                  artists: header.artists)
    }

    private func load() async {
        state = .loading
        do {
            page = try await MusicAPI.browse(id: browseId, params: params)
            state = .loaded
        } catch {
            state = .failed(error.asAppError.errorDescription ?? "Gagal memuat")
        }
    }
}
