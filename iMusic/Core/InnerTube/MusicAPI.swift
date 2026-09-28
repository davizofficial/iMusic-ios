import Foundation

/// All metadata endpoints, ported from the routes in `server.js`.
enum MusicAPI {
    static let searchParams: [String: String] = [
        "songs": "EgWKAQIIAWoMEA4QChADEAQQCRAF",
        "videos": "EgWKAQIQAWoMEA4QChADEAQQCRAF",
        "albums": "EgWKAQIYAWoMEA4QChADEAQQCRAF",
        "artists": "EgWKAQIgAWoMEA4QChADEAQQCRAF",
        "playlists": "EgeKAQQoAEABagwQDhAKEAMQBBAJEAU=",
    ]

    // MARK: Home

    static func home() async throws -> [MediaSection] {
        let d = try await InnerTubeClient.shared.post("browse", body: ["browseId": "FEmusic_home"], ttl: 600)
        guard let sl = JSON.first(d, "sectionListRenderer") as? [String: Any] else { return [] }
        var sections = InnerTubeParser.parseSections(sl["contents"] as? [Any])

        var token = ((sl["continuations"] as? [Any])?.first as? [String: Any])?["nextContinuationData"] as? [String: Any]
        var n = 0
        while let t = token, n < 3, let ctoken = t["continuation"] as? String {
            let d2 = try await InnerTubeClient.shared.post(
                "browse", body: [:],
                query: "&ctoken=\(ctoken)&continuation=\(ctoken)&type=next",
                ttl: 600
            )
            guard let slc = JSON.first(d2, "sectionListContinuation") as? [String: Any] else { break }
            sections.append(contentsOf: InnerTubeParser.parseSections(slc["contents"] as? [Any]))
            token = ((slc["continuations"] as? [Any])?.first as? [String: Any])?["nextContinuationData"] as? [String: Any]
            n += 1
        }
        return sections
    }

    // MARK: Charts

    static func charts() async throws -> [MediaSection] {
        let d = try await InnerTubeClient.shared.post("browse", body: ["browseId": "FEmusic_charts"], ttl: 1800)
        guard let sl = JSON.first(d, "sectionListRenderer") as? [String: Any] else { return [] }
        return InnerTubeParser.parseSections(sl["contents"] as? [Any])
    }

    // MARK: Moods / genres

    static func moods() async throws -> [MoodCategory] {
        let d = try await InnerTubeClient.shared.post("browse", body: ["browseId": "FEmusic_moods_and_genres"], ttl: 3600)
        return JSON.findAll(d, key: "musicNavigationButtonRenderer").compactMap { b -> MoodCategory? in
            guard let bd = b as? [String: Any] else { return nil }
            let click = bd["clickCommand"] as? [String: Any]
            let be = click?["browseEndpoint"] as? [String: Any]
            guard let bid = be?["browseId"] as? String else { return nil }
            var color: String?
            if let solid = bd["solid"] as? [String: Any],
               let v = (solid["leftStripeColor"] as? NSNumber)?.uint32Value {
                color = String(format: "#%06X", v & 0xFFFFFF)
            }
            return MoodCategory(title: JSON.runsText(bd["buttonText"]),
                                color: color,
                                browseId: bid,
                                params: be?["params"] as? String)
        }
    }

    // MARK: Search

    static func search(query: String, filter: String?) async throws -> [MediaSection] {
        var body: [String: Any] = ["query": query]
        if let f = filter, let p = searchParams[f] { body["params"] = p }
        let d = try await InnerTubeClient.shared.post("search", body: body)

        var sections: [MediaSection] = []
        for shelfAny in JSON.findAll(d, key: "musicShelfRenderer") {
            guard let shelf = shelfAny as? [String: Any] else { continue }
            let items = JSON.array(shelf["contents"]).compactMap { c -> MediaItem? in
                guard let cd = c as? [String: Any],
                      let lr = cd["musicResponsiveListItemRenderer"] as? [String: Any] else { return nil }
                return InnerTubeParser.parseListItem(lr)
            }
            if !items.isEmpty {
                sections.append(MediaSection(title: JSON.runsText(shelf["title"]), items: items, list: true))
            }
        }

        // Newer general-search layout: flat itemSectionRenderers.
        if sections.isEmpty {
            var flat: [MediaItem] = []
            var seen = Set<String>()
            for secAny in JSON.findAll(d, key: "itemSectionRenderer") {
                guard let sec = secAny as? [String: Any] else { continue }
                for c in JSON.array(sec["contents"]) {
                    guard let cd = c as? [String: Any],
                          let lr = cd["musicResponsiveListItemRenderer"] as? [String: Any],
                          let it = InnerTubeParser.parseListItem(lr) else { continue }
                    let key = it.videoId ?? it.browseId ?? it.title
                    if !seen.contains(key) { seen.insert(key); flat.append(it) }
                }
            }
            if !flat.isEmpty { sections.append(MediaSection(title: "Results", items: flat, list: true)) }
        }

        if let top = JSON.first(d, "musicCardShelfRenderer") as? [String: Any] {
            let nav = InnerTubeParser.endpointInfo(JSON.first(top["title"], "navigationEndpoint"))
            let item = MediaItem(
                type: nav.videoId != nil ? "song" : (nav.browseType ?? "song"),
                title: JSON.runsText(top["title"]),
                subtitle: JSON.runsText(top["subtitle"]),
                thumbnail: InnerTubeParser.bestThumbnail(top["thumbnail"]),
                videoId: nav.videoId,
                browseId: nav.browseId,
                browseType: nav.browseType
            )
            sections.insert(MediaSection(title: "Top result", items: [item], list: nil), at: 0)
        }
        return sections
    }

    static func suggest(_ q: String) async throws -> [String] {
        let d = try await InnerTubeClient.shared.post("music/get_search_suggestions", body: ["input": q])
        return JSON.findAll(d, key: "searchSuggestionRenderer").compactMap { s -> String? in
            guard let sd = s as? [String: Any] else { return nil }
            let t = JSON.runsText(sd["suggestion"])
            return t.isEmpty ? nil : t
        }
    }

    // MARK: Radio / queue

    static func next(videoId: String?, playlistId: String?) async throws -> NextResult {
        var body: [String: Any] = ["isAudioOnly": true, "tunerSettingValue": "AUTOMIX_SETTING_NORMAL"]
        if let vid = videoId {
            body["videoId"] = vid
            body["playlistId"] = playlistId ?? "RDAMVM\(vid)"
            body["watchEndpointMusicSupportedConfigs"] = [
                "watchEndpointMusicConfig": ["musicVideoType": "MUSIC_VIDEO_TYPE_ATV"],
            ]
        } else if let pid = playlistId {
            body["playlistId"] = pid
        }
        let d = try await InnerTubeClient.shared.post("next", body: body)

        let queue = JSON.findAll(d, key: "playlistPanelVideoRenderer").compactMap { p -> MediaItem? in
            guard let pd = p as? [String: Any], let vid = pd["videoId"] as? String else { return nil }
            let byline = pd["shortBylineText"] ?? pd["longBylineText"]
            return MediaItem(
                type: "song",
                title: Fmt.displayTitle(JSON.runsText(pd["title"])),
                subtitle: JSON.runsText(byline),
                thumbnail: InnerTubeParser.bestThumbnail(pd["thumbnail"]),
                videoId: vid,
                duration: JSON.runsText(pd["lengthText"]),
                artists: InnerTubeParser.runsInfo(pd["longBylineText"])
            )
        }

        var lyricsBrowseId: String?
        var relatedBrowseId: String?
        for tabAny in JSON.findAll(d, key: "tabRenderer") {
            guard let tab = tabAny as? [String: Any],
                  let be = (tab["endpoint"] as? [String: Any])?["browseEndpoint"] as? [String: Any],
                  let bid = be["browseId"] as? String else { continue }
            if bid.hasPrefix("MPLYt") { lyricsBrowseId = bid }
            if bid.hasPrefix("MPTRt") { relatedBrowseId = bid }
        }
        return NextResult(queue: queue, lyricsBrowseId: lyricsBrowseId, relatedBrowseId: relatedBrowseId)
    }

    // MARK: Related

    static func related(browseId: String) async throws -> [MediaSection] {
        let d = try await InnerTubeClient.shared.post("browse", body: ["browseId": browseId], ttl: 1800)
        var sections: [MediaSection] = []
        if let sl = JSON.first(d, "sectionListRenderer") as? [String: Any] {
            sections = InnerTubeParser.parseSections(sl["contents"] as? [Any])
        }
        for gAny in JSON.findAll(d, key: "gridRenderer") {
            guard let g = gAny as? [String: Any] else { continue }
            let items = JSON.array(g["items"]).compactMap { c -> MediaItem? in
                guard let cd = c as? [String: Any] else { return nil }
                if let tr = cd["musicTwoRowItemRenderer"] as? [String: Any] { return InnerTubeParser.parseTwoRow(tr) }
                if let lr = cd["musicResponsiveListItemRenderer"] as? [String: Any] { return InnerTubeParser.parseListItem(lr) }
                return nil
            }
            if !items.isEmpty {
                sections.append(MediaSection(title: JSON.runsText(JSON.first(g["header"], "title")), items: items, list: nil))
            }
        }
        return sections.filter { !$0.items.isEmpty }
    }

    // MARK: Browse (album / playlist / artist / mood)

    static func browse(id rawId: String, params: String?) async throws -> BrowsePage {
        var id = rawId
        if id.range(of: "^(PL|RDCLAK|VLPL|OLAK)", options: .regularExpression) != nil, !id.hasPrefix("VL") {
            id = "VL" + id
        }
        var body: [String: Any] = ["browseId": id]
        if let p = params { body["params"] = p }
        let d = try await InnerTubeClient.shared.post("browse", body: body, ttl: 1800)

        var header: PageHeader?
        let hRaw = JSON.first(d, "musicResponsiveHeaderRenderer")
            ?? JSON.first(d, "musicDetailHeaderRenderer")
            ?? JSON.first(d, "musicImmersiveHeaderRenderer")
            ?? JSON.first(d, "musicVisualHeaderRenderer")
            ?? JSON.first(d, "musicEditablePlaylistDetailHeaderRenderer")
        if let h = hRaw as? [String: Any] {
            let subtitle = [JSON.runsText(h["subtitle"]), JSON.runsText(h["secondSubtitle"])]
                .filter { !$0.isEmpty }.joined(separator: " • ")
            header = PageHeader(
                title: JSON.runsText(h["title"]),
                subtitle: subtitle,
                description: JSON.runsText(h["description"]),
                thumbnail: InnerTubeParser.bestThumbnail(h["thumbnail"] ?? h["foregroundThumbnail"] ?? h),
                artists: InnerTubeParser.runsInfo(h["subtitle"]),
                strapline: JSON.runsText(h["straplineTextOne"])
            )
        }

        var playlistId: String?
        if let wpe = JSON.first(d, "watchPlaylistEndpoint") as? [String: Any] {
            playlistId = wpe["playlistId"] as? String
        }

        var tracks: [MediaItem] = []
        let shelves = JSON.findAll(d, key: "musicShelfRenderer") + JSON.findAll(d, key: "musicPlaylistShelfRenderer")
        for shelfAny in shelves {
            guard let shelf = shelfAny as? [String: Any] else { continue }
            let items = JSON.array(shelf["contents"]).compactMap { c -> MediaItem? in
                guard let cd = c as? [String: Any],
                      let lr = cd["musicResponsiveListItemRenderer"] as? [String: Any] else { return nil }
                return InnerTubeParser.parseListItem(lr)
            }
            let withVideo = items.filter { $0.videoId != nil }
            if !items.isEmpty, withVideo.count >= items.count / 2, tracks.isEmpty {
                tracks = items
            }
        }

        var sections: [MediaSection] = []
        if let sl = JSON.first(d, "sectionListRenderer") as? [String: Any] {
            sections = InnerTubeParser.parseSections(sl["contents"] as? [Any])
                .filter { !($0.list == true && !tracks.isEmpty) }
        }
        if !tracks.isEmpty, let firstVid = tracks.first?.videoId {
            sections = sections.filter { !($0.list == true && $0.items.first?.videoId == firstVid) }
        }

        for gAny in JSON.findAll(d, key: "gridRenderer") {
            guard let g = gAny as? [String: Any] else { continue }
            let items = JSON.array(g["items"]).compactMap { c -> MediaItem? in
                guard let cd = c as? [String: Any],
                      let tr = cd["musicTwoRowItemRenderer"] as? [String: Any] else { return nil }
                return InnerTubeParser.parseTwoRow(tr)
            }
            if !items.isEmpty {
                sections.append(MediaSection(title: JSON.runsText(JSON.first(g["header"], "title")), items: items, list: nil))
            }
        }

        if header?.thumbnail == nil, let t = tracks.first?.thumbnail { header?.thumbnail = t }
        return BrowsePage(header: header, tracks: tracks, sections: sections, playlistId: playlistId)
    }

    // MARK: Resolve shared link

    struct Resolved {
        var kind: String
        var id: String?
        var videoId: String?
        var playlistId: String?
    }

    static func resolve(url raw: String) -> Resolved? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let full = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let comps = URLComponents(string: full) else { return nil }
        let list = comps.queryItems?.first(where: { $0.name == "list" })?.value
        let v = comps.queryItems?.first(where: { $0.name == "v" })?.value
        let path = comps.path
        if let list, v == nil { return Resolved(kind: "playlist", id: list) }
        if let v { return Resolved(kind: "song", videoId: v, playlistId: list) }
        let parts = path.split(separator: "/").map(String.init)
        if parts.count >= 2, parts[0] == "channel" {
            return Resolved(kind: "artist", id: parts[1])
        }
        if parts.count >= 2, parts[0] == "browse" {
            return Resolved(kind: parts[1].hasPrefix("MPRE") ? "album" : "playlist", id: parts[1])
        }
        return nil
    }
}
