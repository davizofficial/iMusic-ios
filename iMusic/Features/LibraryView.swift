import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var player: PlayerModel
    @EnvironmentObject private var library: LibraryStore
    @State private var tab = 0
    @State private var newPlaylistName = ""
    @State private var showNewPlaylist = false

    private let tabs = ["Playlist", "Favorit", "Simpan", "Riwayat", "Unduhan", "Statistik"]
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    ForEach(Array(tabs.enumerated()), id: \.offset) { idx, name in
                        Text(LocalizedStringKey(name)).tag(idx)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Theme.screenPadding)
                .padding(.bottom, 8)

                if tab == 4 {
                    DownloadsView()
                } else {
                    ScrollView {
                        switch tab {
                        case 0: playlists
                        case 1: favorites
                        case 2: saved
                        case 3: history
                        default: stats
                        }
                    }
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gearshape")
                    }
                }
                if tab == 0 {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            newPlaylistName = ""
                            showNewPlaylist = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .alert("Playlist Baru", isPresented: $showNewPlaylist) {
                TextField("Nama", text: $newPlaylistName)
                Button("Buat") {
                    let name = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    library.createPlaylist(name: name)
                }
                Button("Batal", role: .cancel) {}
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: Tabs

    private var playlists: some View {
        Group {
            if library.playlists.isEmpty {
                EmptyStateView(title: "Belum ada playlist", message: "Buat playlist dari tombol + di kanan atas.")
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(library.playlists) { pl in
                        NavigationLink(destination: LocalPlaylistView(playlistId: pl.id)) {
                            VStack(alignment: .leading, spacing: 6) {
                                ArtworkView(url: pl.tracks.first?.thumbnail, cornerRadius: 8)
                                    .frame(height: 150)
                                Text(pl.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Text("\(pl.tracks.count) lagu").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
            }
        }
    }

    private var favorites: some View {
        Group {
            if library.favorites.isEmpty {
                EmptyStateView(title: "Belum ada favorit", message: "Tekan lama lagu lalu pilih Favorit.", systemImage: "heart")
            } else {
                VStack(spacing: 0) {
                    Button {
                        if let first = library.favorites.first {
                            player.play(first, queue: library.favorites)
                        }
                    } label: {
                        Label("Putar Semua", systemImage: "play.fill")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, Theme.screenPadding)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    ForEach(Array(library.favorites.enumerated()), id: \.offset) { idx, song in
                        SongRow(item: song.mediaItem, number: idx + 1, queue: library.favorites.map(\.mediaItem))
                    }
                }
            }
        }
    }

    private var saved: some View {
        Group {
            if library.saved.isEmpty {
                EmptyStateView(title: "Belum ada yang disimpan", message: "Simpan album, playlist, atau artis dari halamannya.", systemImage: "bookmark")
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(Array(library.saved.enumerated()), id: \.offset) { _, item in
                        MediaCard(item: item)
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
            }
        }
    }

    private var history: some View {
        Group {
            if library.history.isEmpty {
                EmptyStateView(title: "Belum ada riwayat", message: "Lagu yang diputar akan muncul di sini.", systemImage: "clock")
            } else {
                ForEach(Array(library.history.enumerated()), id: \.offset) { idx, song in
                    SongRow(item: song.mediaItem, number: idx + 1, queue: library.history.map(\.mediaItem))
                }
            }
        }
    }

    private var stats: some View {
        let rows = library.stats.values
        let totalPlays = rows.reduce(0) { $0 + $1.plays }
        let totalMinutes = Int(rows.reduce(0.0) { $0 + $1.secs } / 60)
        return VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                statCard("\(totalPlays)", "Total putar")
                statCard("\(totalMinutes)", "Menit")
                statCard("\(library.stats.count)", "Lagu")
            }
            .padding(.horizontal, Theme.screenPadding)
            Text("Statistik tersimpan di perangkat ini saja.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, Theme.screenPadding)
        }
        .padding(.vertical, 8)
    }

    private func statCard(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.weight(.bold)).foregroundStyle(Theme.accent)
            Text(LocalizedStringKey(label)).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct LocalPlaylistView: View {
    let playlistId: String
    @EnvironmentObject private var player: PlayerModel
    @EnvironmentObject private var library: LibraryStore

    private var playlist: Playlist? { library.playlists.first { $0.id == playlistId } }

    var body: some View {
        Group {
            if let playlist {
                if playlist.tracks.isEmpty {
                    EmptyStateView(title: "Playlist kosong", message: "Tambahkan lagu lewat menu panjang pada lagu.")
                } else {
                    List {
                        ForEach(Array(playlist.tracks.enumerated()), id: \.offset) { idx, song in
                            SongRow(item: song.mediaItem, number: idx + 1, queue: playlist.tracks.map(\.mediaItem))
                                .listRowInsets(EdgeInsets())
                        }
                        .onDelete { indexSet in
                            for i in indexSet { library.remove(videoId: playlist.tracks[i].videoId, from: playlistId) }
                        }
                    }
                    .listStyle(.plain)
                }
            } else {
                EmptyStateView(title: "Playlist tidak ditemukan", message: "Mungkin sudah dihapus.")
            }
        }
        .navigationTitle(playlist?.name ?? "Playlist")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let playlist, !playlist.tracks.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        player.play(playlist.tracks[0], queue: playlist.tracks)
                    } label: {
                        Image(systemName: "play.fill")
                    }
                }
            }
        }
    }
}
