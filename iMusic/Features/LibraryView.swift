import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var player: PlayerModel
    @EnvironmentObject private var library: LibraryStore
    @State private var newPlaylistName = ""
    @State private var showNewPlaylist = false

    var body: some View {
        NavigationView {
            List {
                // Section 1: Apple Music style navigation list
                Section {
                    NavigationLink(destination: PlaylistsListView()) {
                        Label {
                            HStack {
                                Text("Playlist")
                                Spacer()
                                if !library.playlists.isEmpty {
                                    Text("\(library.playlists.count)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            Image(systemName: "music.note.list")
                                .foregroundStyle(Theme.accent)
                        }
                    }

                    NavigationLink(destination: FavoritesView()) {
                        Label {
                            HStack {
                                Text("Lagu Favorit")
                                Spacer()
                                if !library.favorites.isEmpty {
                                    Text("\(library.favorites.count)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.red)
                        }
                    }

                    NavigationLink(destination: HistoryView()) {
                        Label {
                            HStack {
                                Text("Riwayat Pemutaran")
                                Spacer()
                                if !library.history.isEmpty {
                                    Text("\(library.history.count)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundStyle(.orange)
                        }
                    }

                    NavigationLink(destination: SavedCollectionView()) {
                        Label {
                            HStack {
                                Text("Koleksi Tersimpan")
                                Spacer()
                                if !library.saved.isEmpty {
                                    Text("\(library.saved.count)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            Image(systemName: "bookmark.fill")
                                .foregroundStyle(.blue)
                        }
                    }

                    NavigationLink(destination: DownloadsView()) {
                        Label {
                            Text("Unduhan Offline")
                        } icon: {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }

                    NavigationLink(destination: StatsView()) {
                        Label {
                            Text("Statistik Pemutaran")
                        } icon: {
                            Image(systemName: "chart.bar.xaxis")
                                .foregroundStyle(.purple)
                        }
                    }
                }

                // Section 2: Recently Played section (Apple Music style)
                Section {
                    if library.history.isEmpty {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "clock")
                                    .font(.system(size: 30))
                                    .foregroundStyle(.secondary)
                                Text("Belum Ada Riwayat")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text("Lagu yang Anda putar akan otomatis muncul di sini.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.vertical, 16)
                            Spacer()
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Baru Saja Diputar")
                                    .font(.headline.weight(.bold))
                                Spacer()
                                NavigationLink(destination: HistoryView()) {
                                    Text("Lihat Semua")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                            .padding(.top, 4)

                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                                ForEach(Array(library.history.prefix(6).enumerated()), id: \.offset) { _, song in
                                    Button {
                                        player.play(song, queue: library.history)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 6) {
                                            ArtworkView(url: song.thumbnail, cornerRadius: 8)
                                                .aspectRatio(1, contentMode: .fit)
                                            Text(song.title)
                                                .font(.caption.weight(.medium))
                                                .lineLimit(1)
                                                .foregroundStyle(.primary)
                                            Text(song.artist)
                                                .font(.caption2)
                                                .lineLimit(1)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.bottom, 6)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        newPlaylistName = ""
                        showNewPlaylist = true
                    } label: {
                        Image(systemName: "plus")
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
}

// MARK: - Subviews

struct HistoryView: View {
    @EnvironmentObject private var player: PlayerModel
    @EnvironmentObject private var library: LibraryStore
    @State private var showClearAlert = false

    var body: some View {
        Group {
            if library.history.isEmpty {
                EmptyStateView(title: "Belum ada riwayat",
                               message: "Lagu yang Anda putar akan otomatis tersimpan di sini.",
                               systemImage: "clock")
            } else {
                List {
                    Section {
                        HStack(spacing: 12) {
                            Button {
                                if let first = library.history.first {
                                    player.play(first, queue: library.history)
                                }
                            } label: {
                                Label("Putar Semua", systemImage: "play.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.accent)

                            Button {
                                if let random = library.history.randomElement() {
                                    var shuffled = library.history.shuffled()
                                    shuffled.removeAll { $0.videoId == random.videoId }
                                    shuffled.insert(random, at: 0)
                                    player.play(random, queue: shuffled)
                                }
                            } label: {
                                Label("Acak", systemImage: "shuffle")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.bordered)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                    }

                    Section(header: Text("\(library.history.count) Lagu Terakhir Diputar")) {
                        ForEach(Array(library.history.enumerated()), id: \.element.videoId) { idx, song in
                            SongRow(item: song.mediaItem, number: idx + 1, queue: library.history.map(\.mediaItem))
                                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                        }
                        .onDelete { indexSet in
                            for i in indexSet {
                                if library.history.indices.contains(i) {
                                    library.removeFromHistory(videoId: library.history[i].videoId)
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Riwayat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !library.history.isEmpty {
                    Button(role: .destructive) {
                        showClearAlert = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .accessibilityLabel("Bersihkan Riwayat")
                }
            }
        }
        .confirmationDialog("Bersihkan Riwayat Pemutaran?", isPresented: $showClearAlert, titleVisibility: .visible) {
            Button("Hapus Semua Riwayat", role: .destructive) {
                library.clearHistory()
            }
            Button("Batal", role: .cancel) {}
        } message: {
            Text("Semua daftar lagu di riwayat pemutaran akan dihapus.")
        }
    }
}

struct FavoritesView: View {
    @EnvironmentObject private var player: PlayerModel
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        Group {
            if library.favorites.isEmpty {
                EmptyStateView(title: "Belum ada favorit",
                               message: "Tekan lama lagu lalu pilih Favorit atau ketuk ikon hati pada player.",
                               systemImage: "heart")
            } else {
                List {
                    Section {
                        HStack(spacing: 12) {
                            Button {
                                if let first = library.favorites.first {
                                    player.play(first, queue: library.favorites)
                                }
                            } label: {
                                Label("Putar Semua", systemImage: "play.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.accent)

                            Button {
                                if let random = library.favorites.randomElement() {
                                    var shuffled = library.favorites.shuffled()
                                    shuffled.removeAll { $0.videoId == random.videoId }
                                    shuffled.insert(random, at: 0)
                                    player.play(random, queue: shuffled)
                                }
                            } label: {
                                Label("Acak", systemImage: "shuffle")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.bordered)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                    }

                    Section(header: Text("\(library.favorites.count) Lagu Favorit")) {
                        ForEach(Array(library.favorites.enumerated()), id: \.element.videoId) { idx, song in
                            SongRow(item: song.mediaItem, number: idx + 1, queue: library.favorites.map(\.mediaItem))
                                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                        }
                        .onDelete { indexSet in
                            for i in indexSet {
                                if library.favorites.indices.contains(i) {
                                    library.toggleFavorite(library.favorites[i])
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Lagu Favorit")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PlaylistsListView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var newPlaylistName = ""
    @State private var showNewPlaylist = false

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        Group {
            if library.playlists.isEmpty {
                EmptyStateView(title: "Belum ada playlist",
                               message: "Ketuk tombol + di atas untuk membuat playlist baru.",
                               systemImage: "music.note.list")
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(library.playlists) { pl in
                            NavigationLink(destination: LocalPlaylistView(playlistId: pl.id)) {
                                VStack(alignment: .leading, spacing: 6) {
                                    ArtworkView(url: pl.tracks.first?.thumbnail, cornerRadius: 8)
                                        .aspectRatio(1, contentMode: .fit)
                                    Text(pl.name)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                        .foregroundStyle(.primary)
                                    Text("\(pl.tracks.count) lagu")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Theme.screenPadding)
                    .padding(.vertical, 12)
                }
            }
        }
        .navigationTitle("Playlist")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    newPlaylistName = ""
                    showNewPlaylist = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert("Playlist Baru", isPresented: $showNewPlaylist) {
            TextField("Nama Playlist", text: $newPlaylistName)
            Button("Buat") {
                let name = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                library.createPlaylist(name: name)
            }
            Button("Batal", role: .cancel) {}
        }
    }
}

struct SavedCollectionView: View {
    @EnvironmentObject private var library: LibraryStore
    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        Group {
            if library.saved.isEmpty {
                EmptyStateView(title: "Belum ada yang disimpan",
                               message: "Simpan album, playlist, atau artis dari halamannya.",
                               systemImage: "bookmark")
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(Array(library.saved.enumerated()), id: \.offset) { _, item in
                            MediaCard(item: item)
                        }
                    }
                    .padding(.horizontal, Theme.screenPadding)
                    .padding(.vertical, 12)
                }
            }
        }
        .navigationTitle("Koleksi Tersimpan")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct StatsView: View {
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        ScrollView {
            let rows = Array(library.stats.values)
            let totalPlays = rows.reduce(0) { $0 + $1.plays }
            let totalMinutes = Int(rows.reduce(0.0) { $0 + $1.secs } / 60)
            let topTracks = rows.sorted { $0.plays > $1.plays }.prefix(10)

            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    statCard("\(totalPlays)", "Total Putar", "play.circle.fill")
                    statCard("\(totalMinutes)", "Menit", "clock.fill")
                    statCard("\(library.stats.count)", "Lagu", "music.note")
                }
                .padding(.horizontal, Theme.screenPadding)

                if !topTracks.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Paling Sering Diputar")
                            .font(.headline.weight(.bold))
                            .padding(.horizontal, Theme.screenPadding)

                        VStack(spacing: 8) {
                            ForEach(Array(topTracks.enumerated()), id: \.element.title) { idx, stat in
                                HStack(spacing: 12) {
                                    Text("\(idx + 1)")
                                        .font(.subheadline.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .frame(width: 24, alignment: .trailing)
                                    ArtworkView(url: stat.thumbnail, cornerRadius: 4)
                                        .frame(width: 44, height: 44)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(stat.title)
                                            .font(.subheadline.weight(.medium))
                                            .lineLimit(1)
                                        Text(stat.artist ?? "")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Text("\(stat.plays)×")
                                        .font(.caption.monospacedDigit().weight(.semibold))
                                        .foregroundStyle(Theme.accent)
                                }
                                .padding(.horizontal, Theme.screenPadding)
                            }
                        }
                    }
                }

                Text("Statistik pemutaran tersimpan secara aman di perangkat ini saja.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Theme.screenPadding)
            }
            .padding(.vertical, 16)
        }
        .navigationTitle("Statistik Pemutaran")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func statCard(_ value: String, _ label: String, _ icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(Theme.accent)
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
            Text(LocalizedStringKey(label))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            ToolbarItem(placement: .navigationBarTrailing) {
                if let playlist, !playlist.tracks.isEmpty {
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
