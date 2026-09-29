import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var player: PlayerModel
    @EnvironmentObject private var library: LibraryStore

    @State private var sections: [MediaSection] = []
    @State private var state: LoadState = .loading
    @State private var selectedGenre = "Semua"
    @State private var genreCache: [String: [MediaSection]] = [:]
    @State private var isGenreLoading = false

    private let genres = [
        "Semua", "Pop", "Santai", "Semangat", "Fokus",
        "Indie", "Rock", "Akustik", "Dangdut", "R&B",
        "Jazz", "K-Pop", "Hip-Hop"
    ]

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                genreBar

                Divider().opacity(0.4)

                Group {
                    if isGenreLoading {
                        LoadingView()
                    } else {
                        switch state {
                        case .loading:
                            LoadingView()
                        case .failed(let message):
                            ErrorStateView(message: message) {
                                Task {
                                    if selectedGenre == "Semua" {
                                        await load()
                                    } else {
                                        await loadGenre(selectedGenre)
                                    }
                                }
                            }
                        case .loaded:
                            content
                        }
                    }
                }
            }
            .navigationTitle("Home")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: HistoryView()) {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityLabel("Riwayat Pemutaran")
                }
            }
        }
        .navigationViewStyle(.stack)
        .task {
            if sections.isEmpty { await load() }
        }
    }

    // MARK: - Genre Pills

    private var genreBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(genres, id: \.self) { genre in
                    Button {
                        selectGenre(genre)
                    } label: {
                        Text(genre)
                            .font(.footnote.weight(selectedGenre == genre ? .bold : .medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                selectedGenre == genre
                                    ? Theme.accent
                                    : Color(.secondarySystemFill)
                            )
                            .foregroundStyle(selectedGenre == genre ? Color.white : Color.primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Content

    private var currentSections: [MediaSection] {
        if selectedGenre == "Semua" {
            return sections
        } else {
            return genreCache[selectedGenre] ?? []
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if selectedGenre == "Semua" && !library.history.isEmpty {
                    recentlyPlayed
                }

                ForEach(Array(currentSections.enumerated()), id: \.offset) { _, section in
                    ShelfView(section: section)
                }
            }
            .padding(.vertical, 8)
        }
        .refreshable {
            if selectedGenre == "Semua" {
                await load()
            } else {
                genreCache.removeValue(forKey: selectedGenre)
                await loadGenre(selectedGenre)
            }
        }
    }

    private var recentlyPlayed: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Baru Diputar")
                    .font(.title3.weight(.bold))
                Spacer()
                NavigationLink(destination: HistoryView()) {
                    Text("Lihat Semua")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, Theme.screenPadding)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(Array(library.history.prefix(6).enumerated()), id: \.offset) { _, song in
                    Button {
                        player.play(song, queue: library.history)
                    } label: {
                        HStack(spacing: 10) {
                            ArtworkView(url: song.thumbnail, cornerRadius: 4)
                                .frame(width: 48, height: 48)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(song.title)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Text(song.artist)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(6)
                        .background(Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.screenPadding)
        }
    }

    // MARK: - Actions

    private func selectGenre(_ genre: String) {
        guard genre != selectedGenre else { return }
        selectedGenre = genre
        if genre == "Semua" {
            state = .loaded
            return
        }
        if genreCache[genre] != nil {
            state = .loaded
            return
        }
        Task {
            await loadGenre(genre)
        }
    }

    private func load() async {
        state = .loading
        do {
            sections = try await MusicAPI.home()
            state = .loaded
        } catch {
            state = .failed(error.asAppError.errorDescription ?? "Gagal memuat rekomendasi")
        }
    }

    private func loadGenre(_ genre: String) async {
        isGenreLoading = true
        defer { isGenreLoading = false }
        do {
            let res = try await MusicAPI.search(query: "\(genre) lagu hits", filter: nil)
            genreCache[genre] = res
            state = .loaded
        } catch {
            state = .failed("Gagal memuat kategori \(genre): \(error.localizedDescription)")
        }
    }
}
