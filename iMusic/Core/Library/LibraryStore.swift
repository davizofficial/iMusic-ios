import Combine
import Foundation

struct Playlist: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var tracks: [Song]
}

struct StatEntry: Codable {
    var title: String
    var artist: String?
    var thumbnail: String?
    var plays: Int
    var secs: Double
    var last: Double
}

struct LibrarySettings: Codable {
    var theme: String = "dark"
    var vol: Int = 100
    var sb_on: Bool = true
    var downloadFormat: String = "m4a"

    enum CodingKeys: String, CodingKey {
        case theme, vol, sb_on, downloadFormat
    }
}

extension LibrarySettings {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        theme = try c.decodeIfPresent(String.self, forKey: .theme) ?? "dark"
        vol = try c.decodeIfPresent(Int.self, forKey: .vol) ?? 100
        sb_on = try c.decodeIfPresent(Bool.self, forKey: .sb_on) ?? true
        downloadFormat = try c.decodeIfPresent(String.self, forKey: .downloadFormat) ?? "m4a"
    }
}

/// On-disk shape. Kept identical to the web app's backup file so backups are
/// interchangeable between web and iOS.
struct LibraryData: Codable {
    var app: String = "rich-music"
    var version: Int = 2
    var favorites: [Song] = []
    var playlists: [Playlist] = []
    var saved: [MediaItem] = []
    var history: [Song] = []
    var stats: [String: StatEntry] = [:]
    var settings: LibrarySettings = LibrarySettings()

    enum CodingKeys: String, CodingKey {
        case app, version, favorites, playlists, saved, history, stats, settings
    }
}

extension LibraryData {
    /// Tolerant decoding so older / partial backups still import.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        app = try c.decodeIfPresent(String.self, forKey: .app) ?? "rich-music"
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 2
        favorites = try c.decodeIfPresent([Song].self, forKey: .favorites) ?? []
        playlists = try c.decodeIfPresent([Playlist].self, forKey: .playlists) ?? []
        saved = try c.decodeIfPresent([MediaItem].self, forKey: .saved) ?? []
        history = try c.decodeIfPresent([Song].self, forKey: .history) ?? []
        stats = try c.decodeIfPresent([String: StatEntry].self, forKey: .stats) ?? [:]
        settings = try c.decodeIfPresent(LibrarySettings.self, forKey: .settings) ?? LibrarySettings()
    }
}

@MainActor
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    @Published var favorites: [Song] = []
    @Published var playlists: [Playlist] = []
    @Published var saved: [MediaItem] = []
    @Published var history: [Song] = []
    @Published var stats: [String: StatEntry] = [:]
    @Published var settings = LibrarySettings()

    private let fileURL: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("imusic-library.json")
        load()
    }

    // MARK: Favorites

    func isFavorite(_ videoId: String) -> Bool { favorites.contains { $0.videoId == videoId } }

    func toggleFavorite(_ song: Song) {
        if isFavorite(song.videoId) {
            favorites.removeAll { $0.videoId == song.videoId }
        } else {
            favorites.insert(song, at: 0)
        }
        save()
    }

    // MARK: Playlists

    @discardableResult
    func createPlaylist(name: String) -> Playlist {
        let pl = Playlist(id: "local_\(Int(Date().timeIntervalSince1970 * 1000))", name: name, tracks: [])
        playlists.insert(pl, at: 0)
        save()
        return pl
    }

    func add(_ song: Song, to playlistId: String) {
        guard let i = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        guard !playlists[i].tracks.contains(where: { $0.videoId == song.videoId }) else { return }
        playlists[i].tracks.append(song)
        save()
    }

    func remove(videoId: String, from playlistId: String) {
        guard let i = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        playlists[i].tracks.removeAll { $0.videoId == videoId }
        save()
    }

    func deletePlaylist(_ id: String) {
        playlists.removeAll { $0.id == id }
        save()
    }

    func renamePlaylist(_ id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[i].name = trimmed
        save()
    }

    func moveTrack(in playlistId: String, from: Int, to: Int) {
        guard let i = playlists.firstIndex(where: { $0.id == playlistId }),
              playlists[i].tracks.indices.contains(from),
              playlists[i].tracks.indices.contains(to), from != to else { return }
        let item = playlists[i].tracks.remove(at: from)
        playlists[i].tracks.insert(item, at: to)
        save()
    }

    // MARK: Saved

    func isSaved(_ browseId: String) -> Bool { saved.contains { $0.browseId == browseId } }

    func toggleSaved(_ item: MediaItem) {
        guard let id = item.browseId else { return }
        if isSaved(id) {
            saved.removeAll { $0.browseId == id }
        } else {
            saved.insert(item, at: 0)
        }
        save()
    }

    // MARK: History / stats

    func pushHistory(_ song: Song) {
        history.removeAll { $0.videoId == song.videoId }
        history.insert(song, at: 0)
        if history.count > 100 { history = Array(history.prefix(100)) }

        var entry = stats[song.videoId] ?? StatEntry(title: song.title, artist: song.artist,
                                                     thumbnail: song.thumbnail, plays: 0, secs: 0, last: 0)
        entry.plays += 1
        entry.last = Date().timeIntervalSince1970
        entry.title = song.title
        entry.thumbnail = song.thumbnail
        stats[song.videoId] = entry
        save()
    }

    func clearHistory() {
        history.removeAll()
        save()
    }

    func removeFromHistory(videoId: String) {
        history.removeAll { $0.videoId == videoId }
        save()
    }

    func addListenTime(_ videoId: String, seconds: Double) {
        guard var entry = stats[videoId] else { return }
        entry.secs += seconds
        stats[videoId] = entry
        save()
    }

    // MARK: Settings

    func updateSettings(_ transform: (inout LibrarySettings) -> Void) {
        var s = settings
        transform(&s)
        settings = s
        save()
    }

    // MARK: Backup / restore

    func exportData() -> Data? {
        let data = LibraryData(app: "rich-music", version: 2,
                               favorites: favorites, playlists: playlists,
                               saved: saved, history: history, stats: stats, settings: settings)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        return try? encoder.encode(data)
    }

    func importData(_ data: Data) throws {
        let decoded = try JSONDecoder().decode(LibraryData.self, from: data)
        favorites = decoded.favorites
        playlists = decoded.playlists
        saved = decoded.saved
        history = decoded.history
        stats = decoded.stats
        settings = decoded.settings
        save()
    }

    // MARK: Persistence

    private func save() {
        let data = LibraryData(app: "rich-music", version: 2,
                               favorites: favorites, playlists: playlists,
                               saved: saved, history: history, stats: stats, settings: settings)
        guard let encoded = try? JSONEncoder().encode(data) else { return }
        try? encoded.write(to: fileURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(LibraryData.self, from: data) else { return }
        favorites = decoded.favorites
        playlists = decoded.playlists
        saved = decoded.saved
        history = decoded.history
        stats = decoded.stats
        settings = decoded.settings
    }
}
