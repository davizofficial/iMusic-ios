import AVFoundation
import Combine
import Foundation

@MainActor
final class PlayerModel: ObservableObject {
    @Published private(set) var queue: [Song] = []
    @Published private(set) var index: Int = -1
    @Published private(set) var isPlaying = false
    @Published var shuffle = false
    @Published var repeatMode: RepeatMode = .off
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published var speed: Float = 1
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lyrics: Lyrics = .empty
    @Published private(set) var relatedSections: [Section] = []
    @Published private(set) var sleepMinutes = 0

    private let engine = PlayerEngine()
    private var loadToken = 0
    private var sleepTask: Task<Void, Never>?
    private var listenAccum: Double = 0
    private var listenSongId: String?
    private var lastTick: Double = 0
    private var isLoaded = false
    private var pendingSeek: Double = 0
    private var tickCount = 0
    private var lyricsBrowseId: String?
    private var relatedBrowseId: String?
    private var sponsorSegments: [SponsorSegment] = []
    private var sponsorEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "sb_on") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "sb_on") }
    }

    var current: Song? { queue.indices.contains(index) ? queue[index] : nil }
    var sponsorBlockOn: Bool { sponsorEnabled }

    init() {
        engine.onTick = { [weak self] time, duration in
            Task { @MainActor in self?.handleTick(time: time, duration: duration) }
        }
        engine.onEnded = { [weak self] in
            Task { @MainActor in self?.next(auto: true) }
        }
        engine.onPlayingChanged = { [weak self] playing in
            Task { @MainActor in self?.isPlaying = playing }
        }
        NowPlayingCenter.installCommands(
            play: { [weak self] in Task { @MainActor in self?.resume() } },
            pause: { [weak self] in Task { @MainActor in self?.pause() } },
            toggle: { [weak self] in Task { @MainActor in self?.toggle() } },
            next: { [weak self] in Task { @MainActor in self?.next(auto: false) } },
            previous: { [weak self] in Task { @MainActor in self?.previous() } },
            seek: { [weak self] position in Task { @MainActor in self?.seek(position) } }
        )
        observeInterruptions()
        restoreState()
    }

    // MARK: Persistence

    private func restoreState() {
        let s = PlayerState.load()
        guard !s.queue.isEmpty, s.queue.indices.contains(s.index) else { return }
        queue = s.queue
        index = s.index
        shuffle = s.shuffle
        repeatMode = s.repeatMode
        speed = s.speed
        pendingSeek = max(0, s.position)
        currentTime = pendingSeek
        if let song = current {
            NowPlayingCenter.update(song: song, time: pendingSeek, duration: 0, rate: 0)
        }
    }

    private func persist() {
        let state = PlayerState(queue: queue, index: index, position: currentTime,
                                shuffle: shuffle, repeatMode: repeatMode, speed: speed)
        DispatchQueue.global(qos: .utility).async { state.save() }
    }

    // MARK: Public controls

    func play(_ song: Song, queue newQueue: [Song]? = nil) {
        if let q = newQueue, !q.isEmpty {
            queue = q
            index = q.firstIndex(where: { $0.videoId == song.videoId }) ?? 0
        } else if let i = queue.firstIndex(where: { $0.videoId == song.videoId }) {
            index = i
        } else {
            queue = [song]
            index = 0
        }
        pendingSeek = 0
        persist()
        Haptics.play()
        loadCurrent(buildRadio: newQueue == nil)
    }

    func playItems(_ items: [MediaItem], startAt startIndex: Int = 0) {
        let songs = items.filter { $0.videoId != nil }.map { $0.song }
        guard !songs.isEmpty else { return }
        let idx = min(max(0, startIndex), songs.count - 1)
        play(songs[idx], queue: songs)
    }

    func toggle() {
        guard current != nil else { return }
        Haptics.tap()
        if isPlaying { pause() } else { resume() }
    }

    func resume() {
        guard current != nil else { return }
        AudioSessionManager.activate()
        if isLoaded {
            engine.play()
        } else {
            loadCurrent(buildRadio: false)
        }
    }

    func pause() {
        engine.pause()
        persist()
    }

    func toggleShuffle() {
        shuffle.toggle()
        persist()
        Haptics.tap()
    }

    func next(auto: Bool) {
        guard !queue.isEmpty else { return }
        if repeatMode == .one, auto {
            engine.seek(0)
            engine.play()
            return
        }
        var nextIndex: Int
        if shuffle {
            let others = queue.indices.filter { $0 != index }
            nextIndex = others.randomElement() ?? index
        } else {
            nextIndex = index + 1
        }
        if nextIndex >= queue.count {
            if repeatMode == .all {
                nextIndex = 0
            } else if auto {
                pause()
                return
            } else {
                nextIndex = 0
            }
        }
        index = nextIndex
        pendingSeek = 0
        persist()
        if !auto { Haptics.selection() }
        loadCurrent(buildRadio: false)
    }

    func previous() {
        if currentTime > 4 { engine.seek(0); persist(); return }
        guard !queue.isEmpty else { return }
        index = index > 0 ? index - 1 : 0
        pendingSeek = 0
        persist()
        Haptics.selection()
        loadCurrent(buildRadio: false)
    }

    func seek(_ time: Double) {
        engine.seek(time)
        currentTime = time
        persist()
        if let song = current {
            NowPlayingCenter.update(song: song, time: time, duration: duration, rate: isPlaying ? 1 : 0)
        }
    }

    func cycleRepeat() {
        repeatMode = RepeatMode(rawValue: (repeatMode.rawValue + 1) % 3) ?? .off
        persist()
        Haptics.tap()
    }

    func setSpeed(_ value: Float) {
        speed = value
        engine.setRate(value)
        persist()
    }

    func setSponsorBlock(_ on: Bool) {
        sponsorEnabled = on
    }

    func setSleepTimer(minutes: Int) {
        sleepTask?.cancel()
        sleepMinutes = minutes
        guard minutes > 0 else { return }
        sleepTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(minutes) * 60_000_000_000)
            guard !Task.isCancelled else { return }
            self?.pause()
            self?.sleepMinutes = 0
        }
    }

    // MARK: Queue editing

    func addNext(_ song: Song) {
        guard current != nil else { play(song); return }
        var s = song
        s.isUserQueued = true
        queue.insert(s, at: min(index + 1, queue.count))
        persist()
    }

    func addToQueue(_ song: Song) {
        guard current != nil else { play(song); return }
        var s = song
        s.isUserQueued = true
        var i = index + 1
        while i < queue.count, queue[i].isUserQueued { i += 1 }
        queue.insert(s, at: i)
        persist()
    }

    func removeFromQueue(at i: Int) {
        guard i >= 0, i < queue.count, i != index else { return }
        if i < index { index -= 1 }
        queue.remove(at: i)
        persist()
    }

    /// Mirrors `Array.move(fromOffsets:toOffset:)`: `to` is the destination gap
    /// in the pre-removal array, so moving down shifts the insert index back one.
    func moveQueueItem(from: Int, to: Int) {
        guard queue.indices.contains(from), from != to, to >= 0, to <= queue.count else { return }
        let item = queue.remove(at: from)
        let dest = min(max(to > from ? to - 1 : to, 0), queue.count)
        queue.insert(item, at: dest)
        if from == index {
            index = dest
        } else if from < index {
            index -= 1
            if dest <= index { index += 1 }
        } else if dest <= index {
            index += 1
        }
        persist()
    }

    func clearUserQueue() {
        queue = queue.enumerated().filter { $0.offset <= index || !$0.element.isUserQueued }.map(\.element)
        persist()
    }

    var upcoming: [Song] { index >= 0 ? Array(queue.dropFirst(index + 1)) : [] }

    // MARK: Loading

    private func loadCurrent(buildRadio: Bool) {
        guard let song = current else { return }
        loadToken += 1
        let token = loadToken
        let seekTarget = pendingSeek
        pendingSeek = 0
        isLoading = true
        isLoaded = false
        errorMessage = nil
        currentTime = 0
        duration = 0
        lyrics = .empty
        relatedSections = []
        lyricsBrowseId = nil
        relatedBrowseId = nil
        sponsorSegments = []
        flushListen()
        listenSongId = nil
        lastTick = 0
        AudioSessionManager.activate()
        LibraryStore.shared.pushHistory(song)
        NowPlayingCenter.update(song: song, time: 0, duration: 0, rate: 0)

        Task {
            // Prefer an offline download when present — works with no network.
            if let local = DownloadManager.shared.localURL(for: song.videoId) {
                guard token == loadToken else { return }
                isLoading = false
                startPlayback(url: local, seekTo: seekTarget)
                if buildRadio { Task { await self.fetchRadio(for: song, token: token) } }
                Task { await self.loadLyrics(for: song, token: token) }
                return
            }
            do {
                let stream = try await StreamResolver.resolve(videoId: song.videoId)
                guard token == loadToken else { return }
                isLoading = false
                startPlayback(url: stream.url, seekTo: seekTarget)
                if buildRadio { Task { await self.fetchRadio(for: song, token: token) } }
                Task { await self.loadLyrics(for: song, token: token) }
                Task { await self.loadSponsor(for: song.videoId, token: token) }
            } catch {
                guard token == loadToken else { return }
                isLoading = false
                let appError = error.asAppError
                if appError == .cancelled { return }
                errorMessage = appError.errorDescription
                if !queue.isEmpty { next(auto: true) }
            }
        }
    }

    private func startPlayback(url: URL, seekTo: Double) {
        engine.load(url: url, autoplay: true)
        engine.setRate(speed)
        if seekTo > 0 {
            engine.seek(seekTo)
            currentTime = seekTo
        }
        isLoaded = true
    }

    private func fetchRadio(for song: Song, token: Int) async {
        do {
            let result = try await MusicAPI.next(videoId: song.videoId, playlistId: song.playlistId)
            guard token == loadToken else { return }
            lyricsBrowseId = result.lyricsBrowseId
            relatedBrowseId = result.relatedBrowseId
            guard result.queue.count > 1 else { return }
            let currentSong = current
            let userUpcoming = upcoming.filter { $0.isUserQueued }
            let radio = result.queue
                .filter { $0.videoId != nil && $0.videoId != currentSong?.videoId }
                .map { item -> Song in
                    var s = item.song
                    s.isUserQueued = false
                    return s
                }
                .filter { r in !userUpcoming.contains(where: { $0.videoId == r.videoId }) }
            if let currentSong {
                queue = [currentSong] + userUpcoming + radio
                index = 0
                persist()
            }
        } catch {
            // Radio is best-effort; failure must not stop playback.
        }
    }

    private func loadLyrics(for song: Song, token: Int) async {
        let result = await LyricsAPI.fetch(
            title: song.title,
            artist: song.artist,
            duration: Int(duration),
            browseId: lyricsBrowseId
        )
        guard token == loadToken else { return }
        lyrics = result
    }

    private func loadSponsor(for videoId: String, token: Int) async {
        let segments = await SponsorBlock.fetch(videoId: videoId)
        guard token == loadToken else { return }
        sponsorSegments = segments
    }

    func loadRelated() async {
        guard let song = current else { return }
        var browseId = relatedBrowseId
        if browseId == nil {
            if let result = try? await MusicAPI.next(videoId: song.videoId, playlistId: song.playlistId) {
                relatedBrowseId = result.relatedBrowseId
                browseId = result.relatedBrowseId
            }
        }
        guard let id = browseId else { return }
        if let sections = try? await MusicAPI.related(browseId: id), !sections.isEmpty {
            relatedSections = sections
        }
    }

    // MARK: Tick

    private func handleTick(time: Double, duration newDuration: Double) {
        let delta = time - lastTick
        lastTick = time
        currentTime = time
        if newDuration > 0 { duration = newDuration }
        if let song = current {
            NowPlayingCenter.update(song: song, time: time, duration: duration, rate: isPlaying ? 1 : 0)
            if isPlaying {
                if listenSongId != song.videoId {
                    flushListen()
                    listenSongId = song.videoId
                }
                // Ignore jumps from seeking; only accumulate smooth playback.
                if delta > 0, delta < 2 {
                    listenAccum += delta
                    if listenAccum >= 15 {
                        LibraryStore.shared.addListenTime(song.videoId, seconds: listenAccum)
                        listenAccum = 0
                    }
                }
            }
        }
        // Persist playback position every ~5s while playing.
        tickCount += 1
        if isPlaying, tickCount % 12 == 0 { persist() }
        if sponsorEnabled, !sponsorSegments.isEmpty {
            if let seg = sponsorSegments.first(where: { time >= $0.start && time < $0.end - 0.3 }) {
                engine.seek(seg.end)
            }
        }
    }

    private func flushListen() {
        if listenAccum > 0, let id = listenSongId {
            LibraryStore.shared.addListenTime(id, seconds: listenAccum)
        }
        listenAccum = 0
    }

    private func observeInterruptions() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self,
                  let info = note.userInfo,
                  let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            Task { @MainActor in
                if type == .ended {
                    AudioSessionManager.activate()
                    self.engine.play()
                } else {
                    self.isPlaying = false
                }
            }
        }
    }
}
