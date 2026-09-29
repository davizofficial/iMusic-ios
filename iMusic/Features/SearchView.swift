import SwiftUI
import UIKit

struct SearchView: View {
    @State private var query = ""
    @State private var sections: [MediaSection] = []
    @State private var suggestions: [String] = []
    @State private var state: LoadState = .loaded
    @State private var filter = "all"
    @State private var suggestTask: Task<Void, Never>?

    private let filters = ["all", "songs", "videos", "albums", "artists", "playlists"]

    var body: some View {
        NavigationView {
            Group {
                switch state {
                case .loading:
                    LoadingView()
                case .failed(let message):
                    ErrorStateView(message: message) { Task { await runSearch(query) } }
                case .loaded:
                    if query.isEmpty {
                        idleContent
                    } else {
                        resultsContent
                    }
                }
            }
            .navigationTitle("Cari")
            .searchable(text: $query, prompt: "Lagu, artis, album…")
            .onSubmit(of: .search) { Task { await runSearch(query) } }
            .onChange(of: query) { newValue in
                suggestTask?.cancel()
                guard !newValue.trimmingCharacters(in: .whitespaces).isEmpty else {
                    suggestions = []
                    return
                }
                suggestTask = Task {
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    guard !Task.isCancelled else { return }
                    if let list = try? await MusicAPI.suggest(newValue) {
                        suggestions = Array(list.prefix(6))
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var idleContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !library.history.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Baru Diputar").font(.title3.weight(.bold)).padding(.horizontal, Theme.screenPadding)
                        ForEach(Array(library.history.prefix(6).enumerated()), id: \.offset) { idx, song in
                            SongRow(item: song.mediaItem, number: idx + 1, queue: library.history.map(\.mediaItem))
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var resultsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(suggestions, id: \.self) { s in
                            Button {
                                query = s
                                suggestions = []
                                Task { await runSearch(s) }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                                    Text(s)
                                    Spacer()
                                }
                                .padding(.horizontal, Theme.screenPadding)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(filters, id: \.self) { f in
                            Button {
                                filter = f
                                Task { await runSearch(query) }
                            } label: {
                                Text(f.capitalized)
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(filter == f ? Color.primary : Theme.cardBackground)
                                    .foregroundStyle(filter == f ? Color(.systemBackground) : .primary)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Theme.screenPadding)
                }
                ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                    ShelfView(section: section)
                }
            }
            .padding(.vertical, 8)
        }
    }

    @EnvironmentObject private var library: LibraryStore

    private func runSearch(_ text: String) async {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { sections = []; return }
        state = .loading
        do {
            sections = try await MusicAPI.search(query: q, filter: filter == "all" ? nil : filter)
            state = .loaded
        } catch {
            state = .failed(error.asAppError.errorDescription ?? "Pencarian gagal")
        }
    }
}
