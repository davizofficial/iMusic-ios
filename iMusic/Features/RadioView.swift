import SwiftUI

/// Radio: start an endless station from any recent song, or jump into a mood
/// station. Playing a song without an explicit queue makes `PlayerModel` build
/// the station automatically from the `/next` endpoint.
struct RadioView: View {
    @EnvironmentObject private var player: PlayerModel
    @EnvironmentObject private var library: LibraryStore
    @State private var moods: [MoodCategory] = []
    @State private var charts: [MediaSection] = []
    @State private var state: LoadState = .loading

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
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
            .navigationTitle("Radio")
        }
        .task { if moods.isEmpty { await load() } }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if !library.history.isEmpty { startFromSong }
                if !moods.isEmpty { moodStations }
                ForEach(Array(charts.enumerated()), id: \.offset) { _, section in
                    ShelfView(section: section)
                }
            }
            .padding(.vertical, 8)
        }
        .refreshable { await load() }
    }

    private var startFromSong: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Mulai Radio")
                .font(.title3.bold())
                .padding(.horizontal, Theme.screenPadding)
            VStack(spacing: 0) {
                ForEach(Array(library.history.prefix(5).enumerated()), id: \.offset) { _, song in
                    Button {
                        player.play(song)
                    } label: {
                        HStack(spacing: 12) {
                            ArtworkView(url: song.thumbnail, cornerRadius: 4)
                                .frame(width: 44, height: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(song.title)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(song.artist)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .foregroundStyle(Theme.accent)
                        }
                        .contentShape(Rectangle())
                        .padding(.horizontal, Theme.screenPadding)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var moodStations: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Stasiun Mood")
                .font(.title3.bold())
                .padding(.horizontal, Theme.screenPadding)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(moods) { MoodCard(mood: $0) }
            }
            .padding(.horizontal, Theme.screenPadding)
        }
    }

    private func load() async {
        state = .loading
        do {
            async let moodsTask = MusicAPI.moods()
            async let chartsTask = MusicAPI.charts()
            moods = try await moodsTask
            charts = try await chartsTask
            state = .loaded
        } catch {
            state = .failed(error.asAppError.errorDescription ?? "Gagal memuat")
        }
    }
}
