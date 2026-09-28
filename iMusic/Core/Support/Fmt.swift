import Foundation

/// Formatting helpers ported from the web app.
enum Fmt {
    static func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// YouTube Music sends durations as "3.45" (m.ss); convert to "3:45".
    static func normalizeDuration(_ raw: String?) -> String {
        let t = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return "" }
        if t.range(of: "^\\d{1,2}(\\.\\d{2}){1,2}$", options: .regularExpression) != nil {
            return t.replacingOccurrences(of: ".", with: ":")
        }
        return t
    }

    /// Strips "(Official Audio)", "[Lyric Video]", "- Topic" and similar noise.
    static func displayTitle(_ title: String?) -> String {
        let raw = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "" }
        var s = raw
        let patterns = [
            "\\s*[\\(\\[]\\s*official\\s*(hd\\s*)?(4k\\s*)?(music\\s*)?(lyric(s)?\\s*)?(audio|video|visualizer|mv)[^\\)\\]]*[\\)\\]]",
            "\\s*[\\(\\[]\\s*(official\\s*)?(hd\\s*)?(music\\s*)?(lyric(s)?\\s*)?(audio|video|visualizer|mv)[^\\)\\]]*[\\)\\]]",
            "\\s*[\\(\\[]\\s*(official\\s*)?(4k|hd|hq|8d(\\s*audio)?|1080p|720p)\\s*[\\)\\]]",
            "\\s*-\\s*(official|lyric(s)?|audio|video|visualizer|topic).*$",
        ]
        for p in patterns {
            s = s.replacingOccurrences(of: p, with: "", options: [.regularExpression, .caseInsensitive])
        }
        s = s.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? raw : s
    }

    static func looksLikePlays(_ s: String?) -> Bool {
        let t = s ?? ""
        return t.range(of: "pemutaran|plays|ditonton|views|x ditonton", options: [.regularExpression, .caseInsensitive]) != nil
    }
}
