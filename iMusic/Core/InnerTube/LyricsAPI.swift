import Foundation

/// Multi-source lyrics, mirroring the strategy in `server.js`:
/// YouTube Music (exact video) -> LRCLIB exact -> LRCLIB fuzzy.
/// NetEase / Textyl / lyrics.ovh are intentionally left out of v1.
enum LyricsAPI {
    static func fetch(title rawTitle: String, artist rawArtist: String, duration: Int, browseId: String?) async -> Lyrics {
        var plain: String?
        var synced: String?
        var source: String?

        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = primaryArtist(rawArtist)

        // 1) YouTube Music lyrics for the exact video (plain but correct).
        if let browseId, !browseId.isEmpty {
            if let ytm = try? await ytmLyrics(browseId: browseId), !ytm.isEmpty {
                plain = ytm
                source = "YouTube Music"
            }
        }

        // 2) LRCLIB exact match.
        if let hit = await lrclibGet(title: title, artist: artist, duration: duration) {
            synced = hit.synced
            plain = plain ?? hit.plain
            source = synced != nil ? "LRCLIB" : (source ?? "LRCLIB")
        }

        // 3) LRCLIB fuzzy search.
        if synced == nil {
            let results = await lrclibSearch(track: title, artist: artist)
            if let best = pickBest(results, title: title, artist: artist, duration: duration) {
                synced = best.synced
                plain = plain ?? best.plain
                if best.synced != nil { source = "LRCLIB" }
            }
        }

        let lines = synced.map { Lyrics.parse($0) } ?? []
        return Lyrics(synced: synced, plain: plain, source: source, lines: lines)
    }

    // MARK: Helpers

    private static func primaryArtist(_ a: String) -> String {
        let first = a.components(separatedBy: CharacterSet(charactersIn: ",&•·")).first ?? a
        var s = first
        for token in [" feat.", " feat ", " ft.", " ft ", " with ", " x ", " vs."] {
            if let r = s.range(of: token, options: .caseInsensitive) {
                s = String(s[s.startIndex..<r.lowerBound])
            }
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    private static func ytmLyrics(browseId: String) async throws -> String? {
        let d = try await InnerTubeClient.shared.post("browse", body: ["browseId": browseId])
        for shelfAny in JSON.findAll(d, key: "musicDescriptionShelfRenderer") {
            guard let shelf = shelfAny as? [String: Any] else { continue }
            let text = JSON.runsText(shelf["description"])
            if text.count > 20 { return text }
        }
        return nil
    }

    private struct LrcHit {
        var trackName: String
        var artistName: String
        var duration: Double
        var synced: String?
        var plain: String?
        var instrumental: Bool
    }

    private static func lrclibGet(title: String, artist: String, duration: Int) async -> LrcHit? {
        guard !title.isEmpty else { return nil }
        var comps = URLComponents(string: "https://lrclib.net/api/get")!
        var items = [URLQueryItem(name: "track_name", value: title),
                     URLQueryItem(name: "artist_name", value: artist)]
        if duration > 0 { items.append(URLQueryItem(name: "duration", value: String(duration))) }
        comps.queryItems = items
        guard let url = comps.url else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 5
        req.setValue("iMusic/1.0", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if (obj["instrumental"] as? Bool) == true { return nil }
        let synced = obj["syncedLyrics"] as? String
        let plain = obj["plainLyrics"] as? String
        guard synced != nil || plain != nil else { return nil }
        return LrcHit(trackName: obj["trackName"] as? String ?? title,
                      artistName: obj["artistName"] as? String ?? artist,
                      duration: (obj["duration"] as? NSNumber)?.doubleValue ?? 0,
                      synced: synced, plain: plain, instrumental: false)
    }

    private static func lrclibSearch(track: String, artist: String) async -> [LrcHit] {
        guard !track.isEmpty else { return [] }
        var comps = URLComponents(string: "https://lrclib.net/api/search")!
        comps.queryItems = [URLQueryItem(name: "track_name", value: track),
                            URLQueryItem(name: "artist_name", value: artist)]
        guard let url = comps.url else { return [] }
        var req = URLRequest(url: url)
        req.timeoutInterval = 5
        req.setValue("iMusic/1.0", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return arr.compactMap { obj -> LrcHit? in
            if (obj["instrumental"] as? Bool) == true { return nil }
            let synced = obj["syncedLyrics"] as? String
            let plain = obj["plainLyrics"] as? String
            guard synced != nil || plain != nil else { return nil }
            return LrcHit(trackName: obj["trackName"] as? String ?? "",
                          artistName: obj["artistName"] as? String ?? "",
                          duration: (obj["duration"] as? NSNumber)?.doubleValue ?? 0,
                          synced: synced, plain: plain, instrumental: false)
        }
    }

    private static func norm(_ s: String) -> String {
        s.lowercased().folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private static func sim(_ a: String, _ b: String) -> Double {
        let na = norm(a), nb = norm(b)
        if na.isEmpty || nb.isEmpty { return 0 }
        if na == nb { return 1 }
        if na.contains(nb) || nb.contains(na) { return 0.85 }
        let aw = Set(na.split(separator: " ")), bw = Set(nb.split(separator: " "))
        let hit = aw.intersection(bw).count
        return Double(hit) / Double(max(aw.count, bw.count))
    }

    private static func pickBest(_ cands: [LrcHit], title: String, artist: String, duration: Int) -> LrcHit? {
        var best: LrcHit?
        var bestScore = 0.0
        for c in cands {
            var score = sim(c.trackName, title) * 2 + sim(c.artistName, artist)
            if duration > 0, c.duration > 0 {
                let diff = abs(c.duration - Double(duration))
                if diff <= 2 { score += 1.2 } else if diff <= 5 { score += 0.6 } else if diff > 20 { score -= 1 }
            }
            if c.synced != nil { score += 0.8 }
            if score > bestScore { bestScore = score; best = c }
        }
        if bestScore >= 1.4 { return best }
        if let b = best, sim(b.trackName, title) >= 0.85, bestScore >= 0.95 { return b }
        return nil
    }
}
