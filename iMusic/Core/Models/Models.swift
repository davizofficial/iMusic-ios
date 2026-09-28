import Foundation

/// A person/artist reference with an optional browse target.
struct ArtistRef: Codable, Hashable {
    var name: String
    var browseId: String?
}

/// One loose media entry. InnerTube mixes songs, albums, playlists, artists
/// and generic pages, so every field is optional and `type` decides behaviour.
struct MediaItem: Codable, Identifiable, Hashable {
    var type: String?
    var title: String = ""
    var subtitle: String?
    var thumbnail: String?
    var videoId: String?
    var browseId: String?
    var browseType: String?
    var params: String?
    var playlistId: String?
    var duration: String?
    var artist: String?
    var artists: [ArtistRef]?
    var album: ArtistRef?

    var id: String { videoId ?? browseId ?? title }

    var isPlayable: Bool { videoId != nil }
    var isPage: Bool {
        guard let t = browseType ?? type else { return false }
        return browseId != nil && ["album", "playlist", "artist", "browse"].contains(t)
    }

    /// Resolve a display artist string from the various shapes InnerTube uses.
    var resolvedArtist: String {
        if let artist, !artist.isEmpty { return artist }
        let fromArtists = (artists ?? []).map(\.name).filter { !$0.isEmpty }.joined(separator: ", ")
        if !fromArtists.isEmpty { return fromArtists }
        if let sub = subtitle, !Fmt.looksLikePlays(sub) { return sub }
        return ""
    }

    var song: Song {
        Song(videoId: videoId ?? "",
             title: Fmt.displayTitle(title),
             artist: resolvedArtist,
             thumbnail: thumbnail ?? "",
             duration: Fmt.normalizeDuration(duration),
             playlistId: playlistId)
    }
}

struct MediaSection: Identifiable, Codable {
    var title: String
    var items: [MediaItem]
    var list: Bool?
    var id: String { "\(title)-\(items.count)-\(items.first?.id ?? "")" }
}

struct PageHeader: Codable {
    var title: String
    var subtitle: String?
    var description: String?
    var thumbnail: String?
    var artists: [ArtistRef]?
    var strapline: String?
}

struct BrowsePage {
    var header: PageHeader?
    var tracks: [MediaItem]
    var sections: [MediaSection]
    var playlistId: String?
}

struct NextResult {
    var queue: [MediaItem]
    var lyricsBrowseId: String?
    var relatedBrowseId: String?
}

struct MoodCategory: Codable, Identifiable, Hashable {
    var title: String
    var color: String?
    var browseId: String
    var params: String?
    var id: String { browseId }
}

struct EndpointInfo {
    var videoId: String?
    var playlistId: String?
    var browseId: String?
    var browseType: String?
    var params: String?
    var watchPlaylist: Bool?
    init() {}
}

/// Slim song shape used by the queue, library and history.
struct Song: Codable, Identifiable, Hashable {
    var videoId: String
    var title: String
    var artist: String
    var thumbnail: String
    var duration: String
    var playlistId: String?
    var isUserQueued: Bool = false

    var id: String { videoId }

    enum CodingKeys: String, CodingKey {
        case videoId, title, artist, thumbnail, duration, playlistId, isUserQueued
    }
}

extension Song {
    /// Tolerant decoding: web backups use different/absent keys.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        videoId = try c.decodeIfPresent(String.self, forKey: .videoId) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        artist = try c.decodeIfPresent(String.self, forKey: .artist) ?? ""
        thumbnail = try c.decodeIfPresent(String.self, forKey: .thumbnail) ?? ""
        duration = try c.decodeIfPresent(String.self, forKey: .duration) ?? ""
        playlistId = try c.decodeIfPresent(String.self, forKey: .playlistId)
        isUserQueued = try c.decodeIfPresent(Bool.self, forKey: .isUserQueued) ?? false
    }
}

enum RepeatMode: Int, Codable {
    case off = 0
    case all = 1
    case one = 2
}
