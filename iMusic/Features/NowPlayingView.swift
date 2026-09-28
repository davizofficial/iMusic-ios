import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject private var player: PlayerModel
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var playButtonSize: CGFloat = 64
    @State private var dragValue = 0.0
    @State private var isDragging = false
    @State private var showQueue = false
    @State private var showLyrics = false
    @State private var showRelated = false
    @State private var bgColor: Color = .black

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 8)
                if showLyrics { lyricsView } else { artwork }
                Spacer(minLength: 8)
                metadata
                scrubber
                controls
                Spacer(minLength: 12)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .sheet(isPresented: $showQueue) { QueueSheet() }
        .sheet(isPresented: $showRelated) { RelatedSheet() }
        .task(id: player.current?.videoId) {
            guard let thumb = player.current?.thumbnail else { bgColor = .black; return }
            bgColor = await DominantColor.color(for: thumb) ?? .black
        }
    }

    // MARK: Pieces

    private var background: some View {
        ZStack {
            Color.black
            LinearGradient(colors: [bgColor.opacity(0.55), .black],
                           startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
            if let url = URL(string: player.current?.thumbnail ?? "") {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.black
                }
                .blur(radius: 60)
                .opacity(0.28)
                .ignoresSafeArea()
            }
        }
        .ignoresSafeArea()
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down").font(.headline)
            }
            .accessibilityLabel("Tutup")
            Spacer()
            Text(showLyrics ? "Lirik" : "Sedang Diputar")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            Button { withAnimation(.easeInOut) { showLyrics.toggle() } } label: {
                Image(systemName: showLyrics ? "music.note" : "quote.bubble")
                    .font(.headline)
            }
            .accessibilityLabel(showLyrics ? "Tampilkan sampul" : "Tampilkan lirik")
            Button { showQueue = true } label: {
                Image(systemName: "list.bullet").font(.headline)
            }
            .accessibilityLabel("Antrean")
            Menu {
                Picker("Kecepatan", selection: Binding(
                    get: { player.speed },
                    set: { player.setSpeed($0) }
                )) {
                    ForEach([Float(0.5), 0.75, 1, 1.25, 1.5, 2], id: \.self) { v in
                        Text(v == 1 ? "Normal" : "\(v, specifier: "%g")×").tag(v)
                    }
                }
                Picker("Timer Tidur", selection: Binding(
                    get: { player.sleepMinutes },
                    set: { player.setSleepTimer(minutes: $0) }
                )) {
                    Text("Nonaktif").tag(0)
                    Text("5 menit").tag(5)
                    Text("15 menit").tag(15)
                    Text("30 menit").tag(30)
                    Text("60 menit").tag(60)
                }
                Button { showRelated = true } label: { Label("Terkait", systemImage: "sparkles") }
            } label: {
                Image(systemName: "ellipsis").font(.headline)
            }
            .accessibilityLabel("Opsi lainnya")
        }
        .foregroundStyle(.white)
        .padding(.top, 8)
    }

    private var artwork: some View {
        ArtworkView(url: player.current?.thumbnail, cornerRadius: 12)
            .frame(maxWidth: 340)
            .aspectRatio(1, contentMode: .fit)
            .shadow(radius: 24, y: 12)
            .scaleEffect(player.isPlaying ? 1 : 0.94)
            .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8),
                       value: player.isPlaying)
            .accessibilityHidden(true)
    }

    private var activeLyricIndex: Int {
        let lines = player.lyrics.lines
        guard !lines.isEmpty else { return -1 }
        var idx = -1
        for (i, line) in lines.enumerated() {
            if player.currentTime >= line.time - 0.2 { idx = i } else { break }
        }
        return idx
    }

    private var lyricsView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if player.lyrics.lines.isEmpty {
                        if let plain = player.lyrics.plain, !plain.isEmpty {
                            Text(plain)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.white)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("Lirik tidak tersedia untuk lagu ini")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    } else {
                        ForEach(Array(player.lyrics.lines.enumerated()), id: \.offset) { idx, line in
                            Text(line.text.isEmpty ? "♪" : line.text)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(colorForLine(idx))
                                .fixedSize(horizontal: false, vertical: true)
                                .id(idx)
                                .onTapGesture { player.seek(line.time) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 48)
            }
            .onChange(of: activeLyricIndex) { idx in
                guard idx >= 0 else { return }
                if reduceMotion {
                    proxy.scrollTo(idx, anchor: .center)
                } else {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        proxy.scrollTo(idx, anchor: .center)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func colorForLine(_ idx: Int) -> Color {
        let active = activeLyricIndex
        if idx == active { return .white }
        if idx < active { return .white.opacity(0.45) }
        return .white.opacity(0.3)
    }

    private var metadata: some View {
        VStack(spacing: 4) {
            Text(player.current?.title ?? "—")
                .font(.title3.bold())
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(player.current?.artist ?? "")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
        }
        .padding(.top, 8)
    }

    private var scrubber: some View {
        VStack(spacing: 2) {
            Slider(value: sliderBinding, in: 0...max(player.duration, 1)) { editing in
                if !editing {
                    player.seek(dragValue)
                    isDragging = false
                }
            }
            .tint(.white)
            .accessibilityLabel("Posisi")
            .accessibilityValue("\(Fmt.time(player.currentTime)) dari \(Fmt.time(player.duration))")
            HStack {
                Text(Fmt.time(isDragging ? dragValue : player.currentTime))
                Spacer()
                Text(Fmt.time(player.duration))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.top, 12)
    }

    private var sliderBinding: Binding<Double> {
        Binding(
            get: { isDragging ? dragValue : player.currentTime },
            set: { newValue in dragValue = newValue; isDragging = true }
        )
    }

    private var repeatLabel: String {
        switch player.repeatMode {
        case .off: return "Nonaktif"
        case .all: return "Semua"
        case .one: return "Satu lagu"
        }
    }

    private var controls: some View {
        HStack(spacing: 36) {
            Button { player.toggleShuffle() } label: {
                Image(systemName: "shuffle")
                    .foregroundStyle(player.shuffle ? Theme.accent : .white)
            }
            .accessibilityLabel("Acak")
            .accessibilityValue(player.shuffle ? "Aktif" : "Nonaktif")
            Button { player.previous() } label: {
                Image(systemName: "backward.fill").font(.title2)
            }
            .accessibilityLabel("Sebelumnya")
            Button { player.toggle() } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: playButtonSize))
            }
            .accessibilityLabel(player.isPlaying ? "Jeda" : "Putar")
            Button { player.next(auto: false) } label: {
                Image(systemName: "forward.fill").font(.title2)
            }
            .accessibilityLabel("Berikutnya")
            Button { player.cycleRepeat() } label: {
                Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                    .foregroundStyle(player.repeatMode == .off ? .white : Theme.accent)
            }
            .accessibilityLabel("Ulangi")
            .accessibilityValue(repeatLabel)
        }
        .foregroundStyle(.white)
        .padding(.top, 18)
    }
}

struct QueueSheet: View {
    @EnvironmentObject private var player: PlayerModel
    @Environment(\.dismiss) private var dismiss

    /// Upcoming rows map to absolute queue indices offset by the current track.
    private var base: Int { player.index + 1 }
    private var upcoming: [Song] { player.upcoming }

    var body: some View {
        NavigationStack {
            List {
                if let current = player.current {
                    Section("Sedang Diputar") {
                        row(current, current: true)
                    }
                }
                if upcoming.isEmpty {
                    Section { Text("Antrean kosong").foregroundStyle(.secondary) }
                } else {
                    Section("Berikutnya") {
                        ForEach(Array(upcoming.enumerated()), id: \.offset) { offset, song in
                            row(song)
                        }
                        .onMove { from, to in
                            guard let f = from.first else { return }
                            player.moveQueueItem(from: f + base, to: to + base)
                        }
                        .onDelete { set in
                            for i in set.sorted(by: >) { player.removeFromQueue(at: i + base) }
                        }
                    }
                }
            }
            .navigationTitle("Antrean")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !upcoming.isEmpty { EditButton() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Bersihkan") { player.clearUserQueue() }
                        .disabled(!upcoming.contains { $0.isUserQueued })
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Selesai") { dismiss() }
                }
            }
        }
    }

    private func row(_ song: Song, current: Bool = false) -> some View {
        HStack(spacing: 10) {
            ArtworkView(url: song.thumbnail, cornerRadius: 4)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.subheadline.weight(current ? .semibold : .regular))
                    .foregroundStyle(current ? Theme.accent : .primary)
                    .lineLimit(1)
                Text(song.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

struct RelatedSheet: View {
    @EnvironmentObject private var player: PlayerModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if player.relatedSections.isEmpty {
                    EmptyStateView(title: "Belum ada rekomendasi",
                                   message: "Coba lagi sebentar lagi.",
                                   systemImage: "sparkles")
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            ForEach(Array(player.relatedSections.enumerated()), id: \.offset) { _, section in
                                ShelfView(section: section)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("Terkait")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Selesai") { dismiss() }
                }
            }
            .task { await player.loadRelated() }
        }
    }
}
