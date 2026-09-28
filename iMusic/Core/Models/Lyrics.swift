import Foundation

struct LyricsLine: Identifiable, Hashable {
    let id = UUID()
    var time: Double
    var text: String
}

struct Lyrics: Equatable {
    var synced: String?
    var plain: String?
    var source: String?
    var lines: [LyricsLine]

    static let empty = Lyrics(synced: nil, plain: nil, source: nil, lines: [])

    var isEmpty: Bool { synced == nil && plain == nil && lines.isEmpty }

    static func parse(_ lrc: String) -> [LyricsLine] {
        var out: [LyricsLine] = []
        for raw in lrc.split(separator: "\n", omittingEmptySubsequences: false) {
            guard let m = raw.range(of: "\\[(\\d+):(\\d+)(?:[.:](\\d+))?\\](.*)", options: .regularExpression) else { continue }
            let line = String(raw[m])
            let pattern = try? NSRegularExpression(pattern: "\\[(\\d+):(\\d+)(?:[.:](\\d+))?\\](.*)")
            guard let res = pattern?.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let minR = Range(res.range(at: 1), in: line),
                  let secR = Range(res.range(at: 2), in: line) else { continue }
            let minutes = Double(line[minR]) ?? 0
            let seconds = Double(line[secR]) ?? 0
            var frac = 0.0
            if let fr = Range(res.range(at: 3), in: line), let fv = Double("0." + line[fr]) { frac = fv }
            var text = ""
            if let tr = Range(res.range(at: 4), in: line) { text = String(line[tr]) }
            out.append(LyricsLine(time: minutes * 60 + seconds + frac,
                                  text: text.trimmingCharacters(in: .whitespaces)))
        }
        return out.sorted { $0.time < $1.time }
    }
}
