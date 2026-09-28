import Foundation

/// Dynamic JSON traversal helpers.
/// InnerTube responses have no stable schema, so we walk `[String: Any]`
/// instead of decoding into rigid Codable structs.
enum JSON {
    static func findAll(_ obj: Any?, key: String) -> [Any] {
        var out: [Any] = []
        collect(obj, key, &out)
        return out
    }

    private static func collect(_ obj: Any?, _ key: String, _ out: inout [Any]) {
        guard let obj else { return }
        if let arr = obj as? [Any] {
            for v in arr { collect(v, key, &out) }
            return
        }
        guard let dict = obj as? [String: Any] else { return }
        for (k, v) in dict {
            if k == key { out.append(v) }
            collect(v, key, &out)
        }
    }

    static func first(_ obj: Any?, _ key: String) -> Any? { findAll(obj, key: key).first }

    static func dict(_ o: Any?) -> [String: Any] { (o as? [String: Any]) ?? [:] }
    static func array(_ o: Any?) -> [Any] { (o as? [Any]) ?? [] }
    static func int(_ o: Any?) -> Int? { (o as? NSNumber)?.intValue }

    /// Joins `runs[].text`, falling back to `simpleText`.
    static func runsText(_ o: Any?) -> String {
        guard let d = o as? [String: Any] else { return "" }
        if let runs = d["runs"] as? [[String: Any]] {
            return runs.compactMap { $0["text"] as? String }.joined()
        }
        return (d["simpleText"] as? String) ?? ""
    }
}
