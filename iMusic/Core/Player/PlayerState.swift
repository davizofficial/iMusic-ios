import Foundation

/// Persisted player snapshot so the queue and playback position survive an app
/// kill (plan §8). Restored paused — the stream is only resolved on first play.
struct PlayerState: Codable {
    var queue: [Song] = []
    var index: Int = -1
    var position: Double = 0
    var shuffle: Bool = false
    var repeatMode: RepeatMode = .off
    var speed: Float = 1

    static var url: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("player-state.json")
    }

    static func load() -> PlayerState {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(PlayerState.self, from: data) else { return PlayerState() }
        return state
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: Self.url, options: .atomic)
    }
}
