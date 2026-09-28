import Foundation

/// Port of the parsing helpers in `server.js`.
enum InnerTubeParser {
    static func upscale(_ url: String?) -> String? {
        guard let url else { return nil }
        if url.contains("googleusercontent.com"),
           let range = url.range(of: "=w\\d+-h\\d+.*$", options: .regularExpression) {
            return url.replacingCharacters(in: range, with: "=w544-h544-l90-rj")
        }
        return url
    }

    static func bestThumbnail(_ o: Any?) -> String? {
        let groups = JSON.findAll(o, key: "thumbnails")
        let all = groups.compactMap { $0 as? [[String: Any]] }.flatMap { $0 }
        guard !all.isEmpty else { return nil }
        var best = all[0]
        var bestW = (best["width"] as? NSNumber)?.intValue ?? -1
        for t in all {
            let w = (t["width"] as? NSNumber)?.intValue ?? 0
            if w >= bestW { bestW = w; best = t }
        }
        return upscale(best["url"] as? String)
    }

    static func runsInfo(_ o: Any?) -> [ArtistRef] {
        guard let d = o as? [String: Any], let runs = d["runs"] as? [[String: Any]] else { return [] }
        var out: [ArtistRef] = []
        for run in runs {
            if let be = (run["navigationEndpoint"] as? [String: Any])?["browseEndpoint"] as? [String: Any],
               let bid = be["browseId"] as? String {
                out.append(ArtistRef(name: run["text"] as? String ?? "", browseId: bid))
            }
        }
        return out
    }

    static func endpointInfo(_ nav: Any?) -> EndpointInfo {
        var info = EndpointInfo()
        guard let d = nav as? [String: Any] else { return info }
        if let we = d["watchEndpoint"] as? [String: Any] {
            info.videoId = we["videoId"] as? String
            info.playlistId = we["playlistId"] as? String
            return info
        }
        if let wpe = d["watchPlaylistEndpoint"] as? [String: Any] {
            info.playlistId = wpe["playlistId"] as? String
            info.watchPlaylist = true
            return info
        }
        if let be = d["browseEndpoint"] as? [String: Any] {
            let id = be["browseId"] as? String
            info.browseId = id
            info.params = be["params"] as? String
            if let id {
                if id.hasPrefix("MPRE") { info.browseType = "album" }
                else if id.hasPrefix("UC") || id.hasPrefix("MPLA") { info.browseType = "artist" }
                else if id.hasPrefix("VL") || id.hasPrefix("PL") || id.hasPrefix("RDCLAK") { info.browseType = "playlist" }
                else { info.browseType = "browse" }
            }
        }
        return info
    }

    static func normalizeDuration(_ s: String?) -> String {
        Fmt.normalizeDuration(s)
    }

    static func parseListItem(_ r: [String: Any]) -> MediaItem? {
        let colDicts: [[String: Any]] = JSON.array(r["flexColumns"]).compactMap {
            ($0 as? [String: Any])?["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any]
        }
        let cols: [Any?] = colDicts.map { $0["text"] }
        let firstCol: Any? = cols.first ?? nil
        let title = firstCol.map { JSON.runsText($0) } ?? ""
        guard !title.isEmpty else { return nil }

        let subtitle = cols.dropFirst().map { JSON.runsText($0) }.filter { !$0.isEmpty }.joined(separator: " • ")

        var videoId = (r["playlistItemData"] as? [String: Any])?["videoId"] as? String
        if videoId == nil, let fc = firstCol as? [String: Any],
           let runs = fc["runs"] as? [[String: Any]] {
            for run in runs {
                if let we = (run["navigationEndpoint"] as? [String: Any])?["watchEndpoint"] as? [String: Any],
                   let vid = we["videoId"] as? String { videoId = vid; break }
            }
        }
        if videoId == nil,
           let we = JSON.first(r["overlay"], "watchEndpoint") as? [String: Any] {
            videoId = we["videoId"] as? String
        }

        let nav = endpointInfo(r["navigationEndpoint"])
        var artists: [ArtistRef] = []
        var albums: [ArtistRef] = []
        for c in cols.dropFirst() {
            for ref in runsInfo(c) {
                if ref.browseId?.hasPrefix("MPRE") == true { albums.append(ref) } else { artists.append(ref) }
            }
        }

        var duration: String?
        if let fixed = JSON.first(r, "musicResponsiveListItemFixedColumnRenderer") as? [String: Any] {
            duration = normalizeDuration(JSON.runsText(fixed["text"]))
        }

        return MediaItem(
            type: videoId != nil ? "song" : (nav.browseType ?? "song"),
            title: title,
            subtitle: subtitle.isEmpty ? nil : subtitle,
            thumbnail: bestThumbnail(r["thumbnail"]),
            videoId: videoId,
            browseId: nav.browseId,
            browseType: nav.browseType,
            params: nav.params,
            playlistId: nav.playlistId,
            duration: duration,
            artists: artists.isEmpty ? nil : artists,
            album: albums.first
        )
    }

    static func parseTwoRow(_ r: [String: Any]) -> MediaItem? {
        var nav = endpointInfo(r["navigationEndpoint"])
        if nav.browseId == nil,
           let title = r["title"] as? [String: Any],
           let runs = title["runs"] as? [[String: Any]],
           let firstNav = runs.first?["navigationEndpoint"] {
            let extra = endpointInfo(firstNav)
            if let bid = extra.browseId {
                nav.browseId = bid
                nav.browseType = extra.browseType
                if nav.params == nil { nav.params = extra.params }
            }
        }

        let title = JSON.runsText(r["title"])
        guard !title.isEmpty else { return nil }

        var type = "song"
        if let bt = nav.browseType, ["album", "playlist", "artist"].contains(bt) { type = bt }
        else if nav.videoId != nil { type = "song" }
        else if nav.playlistId != nil || nav.watchPlaylist == true { type = "playlist" }

        var item = MediaItem(
            type: type,
            title: title,
            subtitle: JSON.runsText(r["subtitle"]),
            thumbnail: bestThumbnail(r),
            videoId: nav.videoId,
            browseId: nav.browseId,
            browseType: nav.browseType,
            params: nav.params,
            playlistId: nav.playlistId,
            artists: runsInfo(r["subtitle"])
        )
        if let tr = JSON.first(r, "musicThumbnailRenderer") as? [String: Any],
           (tr["thumbnailCrop"] as? String) == "MUSIC_THUMBNAIL_CROP_CIRCLE" {
            item.type = "artist"
        }
        return item
    }

    static func parseSections(_ contents: [Any]?) -> [MediaSection] {
        var sections: [MediaSection] = []
        for s in contents ?? [] {
            guard let sd = s as? [String: Any] else { continue }
            if let car = sd["musicCarouselShelfRenderer"] as? [String: Any] {
                let title = JSON.runsText(JSON.first(car["header"], "title"))
                let items = JSON.array(car["contents"]).compactMap { c -> MediaItem? in
                    guard let cd = c as? [String: Any] else { return nil }
                    if let tr = cd["musicTwoRowItemRenderer"] as? [String: Any] { return parseTwoRow(tr) }
                    if let lr = cd["musicResponsiveListItemRenderer"] as? [String: Any] { return parseListItem(lr) }
                    return nil
                }
                if !items.isEmpty { sections.append(MediaSection(title: title, items: items, list: nil)) }
            } else if let shelf = sd["musicShelfRenderer"] as? [String: Any] {
                let items = JSON.array(shelf["contents"]).compactMap { c -> MediaItem? in
                    guard let cd = c as? [String: Any],
                          let lr = cd["musicResponsiveListItemRenderer"] as? [String: Any] else { return nil }
                    return parseListItem(lr)
                }
                if !items.isEmpty {
                    sections.append(MediaSection(title: JSON.runsText(shelf["title"]), items: items, list: true))
                }
            }
        }
        return sections
    }
}
