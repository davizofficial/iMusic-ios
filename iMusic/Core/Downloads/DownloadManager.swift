import Combine
import Foundation

struct DownloadedTrack: Codable, Identifiable, Hashable {
    var videoId: String
    var title: String
    var artist: String
    var thumbnail: String
    var duration: String
    var fileName: String
    var format: String
    var bytes: Int64

    var id: String { videoId }

    var localURL: URL { DownloadManager.downloadsDir.appendingPathComponent(fileName) }

    var song: Song {
        Song(videoId: videoId, title: title, artist: artist,
             thumbnail: thumbnail, duration: duration, playlistId: nil)
    }
}

/// Offline downloads. Native `.m4a` is the default; `.mp3` goes through the
/// third-party converter (see `MP3Converter`).
@MainActor
final class DownloadManager: ObservableObject {
    static let shared = DownloadManager()

    nonisolated static let downloadsDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    @Published private(set) var tracks: [DownloadedTrack] = []
    @Published private(set) var active: Set<String> = []
    @Published private(set) var batchDone = 0
    @Published private(set) var batchTotal = 0
    @Published var lastError: String?

    private let indexURL: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        indexURL = base.appendingPathComponent("downloads.json")
        loadIndex()
    }

    // MARK: Queries

    func isDownloaded(_ videoId: String) -> Bool {
        tracks.contains { $0.videoId == videoId }
    }

    func localURL(for videoId: String) -> URL? {
        guard let track = tracks.first(where: { $0.videoId == videoId }) else { return nil }
        let url = Self.downloadsDir.appendingPathComponent(track.fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    var isBatchRunning: Bool { batchTotal > 0 }

    // MARK: Download

    func download(_ song: Song, format: String) async {
        guard !song.videoId.isEmpty,
              !isDownloaded(song.videoId),
              !active.contains(song.videoId) else { return }

        active.insert(song.videoId)
        defer { active.remove(song.videoId) }

        let ext = format == "mp3" ? "mp3" : "m4a"
        let fileName = Self.fileName(for: song, ext: ext)
        do {
            let remote: URL
            if ext == "mp3" {
                remote = try await MP3Converter.convert(videoId: song.videoId)
            } else {
                remote = try await StreamResolver.resolve(videoId: song.videoId).url
            }
            let size = try await fetchToFile(url: remote, fileName: fileName)
            let track = DownloadedTrack(videoId: song.videoId, title: song.title, artist: song.artist,
                                        thumbnail: song.thumbnail, duration: song.duration,
                                        fileName: fileName, format: ext, bytes: size)
            tracks.removeAll { $0.videoId == track.videoId }
            tracks.insert(track, at: 0)
            persistIndex()
            Haptics.success()
        } catch {
            lastError = "Gagal mengunduh \"\(song.title)\": \(error.asAppError.errorDescription ?? "coba lagi")"
            Haptics.warning()
        }
    }

    func downloadPlaylist(_ songs: [Song], format: String) async {
        let list = songs.filter { !$0.videoId.isEmpty }
        guard !list.isEmpty else { return }
        batchTotal = list.count
        batchDone = 0
        for song in list {
            await download(song, format: format)
            batchDone += 1
        }
        batchTotal = 0
    }

    func delete(_ videoId: String) {
        guard let track = tracks.first(where: { $0.videoId == videoId }) else { return }
        try? FileManager.default.removeItem(at: track.localURL)
        tracks.removeAll { $0.videoId == videoId }
        persistIndex()
    }

    // MARK: Internals

    private func fetchToFile(url: URL, fileName: String) async throws -> Int64 {
        var req = URLRequest(url: url)
        req.setValue(AppConfig.userAgent, forHTTPHeaderField: "User-Agent")
        let (tempURL, response) = try await URLSession.shared.download(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AppError.network
        }
        let dest = Self.downloadsDir.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: dest.path) {
            try? FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.moveItem(at: tempURL, to: dest)
        let attrs = try? FileManager.default.attributesOfItem(atPath: dest.path)
        return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
    }

    private static func fileName(for song: Song, ext: String) -> String {
        let raw = "\(song.artist) - \(song.title)"
            .replacingOccurrences(of: "[\\\\/:*?\"<>|]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        let base = raw.isEmpty ? song.videoId : String(raw.prefix(80))
        return "\(base)-\(song.videoId).\(ext)"
    }

    private func persistIndex() {
        guard let data = try? JSONEncoder().encode(tracks) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([DownloadedTrack].self, from: data) else { return }
        // Drop entries whose file disappeared (e.g. restored backup).
        tracks = decoded.filter { FileManager.default.fileExists(atPath: $0.localURL.path) }
    }
}
