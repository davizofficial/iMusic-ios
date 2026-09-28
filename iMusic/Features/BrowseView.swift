import SwiftUI

struct BrowseView: View {
    @State private var moods: [MoodCategory] = []
    @State private var charts: [Section] = []
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
            .navigationTitle("Jelajahi")
        }
        .task { if moods.isEmpty { await load() } }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if !moods.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Mood & Genre").font(.title3.bold()).padding(.horizontal, Theme.screenPadding)
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(moods) { MoodCard(mood: $0) }
                        }
                        .padding(.horizontal, Theme.screenPadding)
                    }
                }
                ForEach(Array(charts.enumerated()), id: \.offset) { _, section in
                    ShelfView(section: section)
                }
            }
            .padding(.vertical, 8)
        }
        .refreshable { await load() }
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
