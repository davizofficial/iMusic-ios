import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var player: PlayerModel
    @EnvironmentObject private var library: LibraryStore
    @State private var sections: [Section] = []
    @State private var state: LoadState = .loading

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
            .navigationTitle("Home")
        }
        .task { if sections.isEmpty { await load() } }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if !library.history.isEmpty { recentlyPlayed }
                ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                    ShelfView(section: section)
                }
            }
            .padding(.vertical, 8)
        }
        .refreshable { await load() }
    }

    private var recentlyPlayed: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Baru Diputar")
                .font(.title3.bold())
                .padding(.horizontal, Theme.screenPadding)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(Array(library.history.prefix(6).enumerated()), id: \.offset) { _, song in
                    Button {
                        player.play(song)
                    } label: {
                        HStack(spacing: 10) {
                            ArtworkView(url: song.thumbnail, cornerRadius: 4)
                                .frame(width: 52, height: 52)
                            Text(song.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .background(Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.screenPadding)
        }
    }

    private func load() async {
        state = .loading
        do {
            sections = try await MusicAPI.home()
            state = .loaded
        } catch {
            state = .failed(error.asAppError.errorDescription ?? "Gagal memuat")
        }
    }
}
