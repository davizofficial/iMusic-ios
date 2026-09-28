import Foundation

/// SponsorBlock: skip intros / sponsor reads.
struct SponsorSegment: Hashable {
    var category: String
    var start: Double
    var end: Double
}

enum SponsorBlock {
    static func fetch(videoId: String) async -> [SponsorSegment] {
        let cats = "[\"sponsor\",\"selfpromo\",\"interaction\",\"intro\",\"outro\",\"music_offtopic\"]"
        let encoded = cats.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cats
        guard let url = URL(string: "https://sponsor.ajay.app/api/skipSegments?videoID=\(videoId)&categories=\(encoded)") else { return [] }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
            return arr.compactMap { s -> SponsorSegment? in
                guard (s["actionType"] as? String) == "skip",
                      let seg = s["segment"] as? [NSNumber], seg.count >= 2 else { return nil }
                return SponsorSegment(category: s["category"] as? String ?? "",
                                      start: seg[0].doubleValue,
                                      end: seg[1].doubleValue)
            }
        } catch {
            return []
        }
    }
}
