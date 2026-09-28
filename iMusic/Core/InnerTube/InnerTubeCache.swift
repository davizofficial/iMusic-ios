import Foundation

/// Two-tier (memory + disk) cache for InnerTube POST responses, keyed by
/// endpoint + client + query + body. InnerTube is POST-only, so `URLCache`
/// cannot help; this is the replacement (plan §4.1).
///
/// `allowExpired` enables read-only offline mode: when the network fails the
/// last successful response is served even past its TTL.
final class InnerTubeCache {
    static let shared = InnerTubeCache()

    private var mem: [String: (expiry: Date, obj: [String: Any])] = [:]
    private let lock = NSLock()
    private let dir: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        dir = base.appendingPathComponent("ITCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func get(_ key: String, allowExpired: Bool) -> [String: Any]? {
        lock.lock()
        defer { lock.unlock() }
        if let hit = mem[key], allowExpired || hit.expiry > Date() {
            return hit.obj
        }
        let url = dir.appendingPathComponent(key + ".json")
        guard let data = try? Data(contentsOf: url),
              let wrapper = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let expiryEpoch = (wrapper["e"] as? NSNumber)?.doubleValue,
              let obj = wrapper["d"] as? [String: Any] else { return nil }
        let expiry = Date(timeIntervalSince1970: expiryEpoch)
        guard allowExpired || expiry > Date() else { return nil }
        mem[key] = (expiry, obj)
        return obj
    }

    func set(_ key: String, _ obj: [String: Any], ttl: TimeInterval) {
        let expiry = Date().addingTimeInterval(ttl)
        lock.lock()
        mem[key] = (expiry, obj)
        lock.unlock()
        let wrapper: [String: Any] = ["e": expiry.timeIntervalSince1970, "d": obj]
        guard let data = try? JSONSerialization.data(withJSONObject: wrapper) else { return }
        try? data.write(to: dir.appendingPathComponent(key + ".json"), options: .atomic)
    }
}
