import SwiftUI
import UIKit

enum Theme {
    static let accent = Color(red: 0.98, green: 0.14, blue: 0.23)
    static let cardBackground = Color(.secondarySystemBackground)
    static let screenPadding: CGFloat = 16
    static let cardWidth: CGFloat = 150
}

// MARK: - Artwork

struct ArtworkView: View {
    let url: String?
    var cornerRadius: CGFloat = 6

    var body: some View {
        Group {
            if let u = URL(string: url ?? ""), !(url ?? "").isEmpty {
                AsyncImage(url: u) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var placeholder: some View {
        ZStack {
            Color(.tertiarySystemFill)
            Image(systemName: "music.note")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Song row

extension Song {
    var mediaItem: MediaItem {
        MediaItem(type: "song", title: title, subtitle: artist, thumbnail: thumbnail,
                  videoId: videoId, playlistId: playlistId, duration: duration, artist: artist)
    }
}

struct SongRow: View {
    let item: MediaItem
    var number: Int?
    var queue: [MediaItem]?
    var trailing: AnyView?

    @EnvironmentObject private var player: PlayerModel
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var downloads: DownloadManager
    @State private var showAddSheet = false

    private var isCurrent: Bool { player.current?.videoId == item.videoId }

    var body: some View {
        Button(action: play) {
            HStack(spacing: 12) {
                if let number {
                    Text("\(number)")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(isCurrent ? Theme.accent : .secondary)
                        .frame(width: 22, alignment: .trailing)
                }
                ArtworkView(url: item.thumbnail, cornerRadius: 4)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Fmt.displayTitle(item.title))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(isCurrent ? Theme.accent : .primary)
                        .lineLimit(1)
                    Text(item.resolvedArtist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if let duration = item.duration, !duration.isEmpty {
                    Text(Fmt.normalizeDuration(duration))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if let trailing { trailing }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, Theme.screenPadding)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .contextMenu { menu }
        .sheet(isPresented: $showAddSheet) {
            AddToPlaylistSheet(song: item.song)
        }
    }

    @ViewBuilder
    private var menu: some View {
        Button { player.addNext(item.song) } label: { Label("Putar Berikutnya", systemImage: "text.line.first.and.arrowtriangle.forward") }
        Button { player.addToQueue(item.song) } label: { Label("Tambah ke Antrean", systemImage: "text.line.last.and.arrowtriangle.forward") }
        Button {
            library.toggleFavorite(item.song)
        } label: {
            Label(library.isFavorite(item.videoId ?? "") ? "Hapus dari Favorit" : "Favorit",
                  systemImage: library.isFavorite(item.videoId ?? "") ? "heart.slash" : "heart")
        }
        Button { showAddSheet = true } label: { Label("Tambah ke Playlist", systemImage: "text.badge.plus") }
        if let videoId = item.videoId {
            Button {
                Task { await downloads.download(item.song, format: library.settings.downloadFormat) }
            } label: {
                Label(downloads.isDownloaded(videoId) ? "Sudah diunduh" : "Unduh",
                      systemImage: "arrow.down.circle")
            }
            .disabled(downloads.isDownloaded(videoId))
        }
        if let videoId = item.videoId,
           let shareURL = URL(string: "https://music.youtube.com/watch?v=\(videoId)") {
            ShareLink(item: shareURL) { Label("Bagikan", systemImage: "square.and.arrow.up") }
        }
        if let artist = item.artists?.first, let browseId = artist.browseId {
            NavigationLink(destination: DetailView(browseId: browseId, kind: "artist")) {
                Label("Buka Artis", systemImage: "music.mic")
            }
        }
    }

    private func play() {
        guard item.videoId != nil else { return }
        if let queue, !queue.isEmpty {
            let start = queue.firstIndex(where: { $0.videoId == item.videoId }) ?? 0
            player.playItems(queue, startAt: start)
        } else {
            player.play(item.song)
        }
    }
}

// MARK: - Add to playlist

struct AddToPlaylistSheet: View {
    let song: Song
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        ArtworkView(url: song.thumbnail, cornerRadius: 4)
                            .frame(width: 44, height: 44)
                        VStack(alignment: .leading) {
                            Text(song.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(song.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                Section("Buat baru") {
                    HStack {
                        TextField("Nama playlist", text: $newName)
                        Button("Buat") {
                            let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !name.isEmpty else { return }
                            let pl = library.createPlaylist(name: name)
                            library.add(song, to: pl.id)
                            dismiss()
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                if !library.playlists.isEmpty {
                    Section("Playlist kamu") {
                        ForEach(library.playlists) { pl in
                            Button {
                                library.add(song, to: pl.id)
                                dismiss()
                            } label: {
                                HStack {
                                    Text(pl.name)
                                    Spacer()
                                    Text("\(pl.tracks.count)").foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Tambah ke Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Media card

struct MediaCard: View {
    let item: MediaItem
    @EnvironmentObject private var player: PlayerModel

    var body: some View {
        if item.isPage, let browseId = item.browseId {
            NavigationLink(destination: DetailView(browseId: browseId, kind: item.browseType ?? "browse")) {
                card
            }
            .buttonStyle(.plain)
        } else {
            Button {
                guard item.videoId != nil else { return }
                player.play(item.song)
            } label: {
                card
            }
            .buttonStyle(.plain)
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 6) {
            ArtworkView(url: item.thumbnail, cornerRadius: item.type == "artist" ? 75 : 8)
                .frame(width: Theme.cardWidth, height: Theme.cardWidth)
            Text(Fmt.displayTitle(item.title))
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            Text(item.subtitle ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: Theme.cardWidth, alignment: .leading)
    }
}

// MARK: - Shelf

struct ShelfView: View {
    let section: Section

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !section.title.isEmpty {
                Text(section.title)
                    .font(.title3.bold())
                    .padding(.horizontal, Theme.screenPadding)
            }
            if section.list == true {
                VStack(spacing: 0) {
                    ForEach(Array(section.items.enumerated()), id: \.offset) { idx, item in
                        SongRow(item: item, number: idx + 1, queue: section.items)
                    }
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                            MediaCard(item: item)
                        }
                    }
                    .padding(.horizontal, Theme.screenPadding)
                }
            }
        }
    }
}

// MARK: - Mood card

struct MoodCard: View {
    let mood: MoodCategory
    private let fallback: [Color] = [.pink, .orange, .purple, .blue, .green, .red, .indigo, .teal]

    private var color: Color {
        if let hex = mood.color, let c = Color(hex: hex) { return c }
        return fallback[abs(mood.title.hashValue) % fallback.count]
    }

    var body: some View {
        NavigationLink(destination: DetailView(browseId: mood.browseId, kind: "browse", params: mood.params)) {
            ZStack(alignment: .topLeading) {
                color
                Text(mood.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(12)
            }
            .frame(height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt64(s, radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }
}

// MARK: - States

struct EmptyStateView: View {
    let title: String
    let message: String
    var systemImage: String = "music.note"

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.vertical, 48)
    }
}

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Memuat…").font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

struct ErrorStateView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text("Terjadi kesalahan").font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Coba lagi", action: retry)
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.vertical, 48)
    }
}

enum LoadState: Equatable {
    case loading
    case loaded
    case failed(String)
}
