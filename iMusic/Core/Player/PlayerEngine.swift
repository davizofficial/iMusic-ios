import AVFoundation
import Foundation

/// Thin wrapper around a single `AVPlayer`.
///
/// A single player (not `AVQueuePlayer`) is used because Apple Music-style
/// "Play Next" inserts into the middle of the queue, which `AVQueuePlayer`
/// handles poorly.
final class PlayerEngine {
    let player = AVPlayer()

    var onTick: ((Double, Double) -> Void)?
    var onEnded: (() -> Void)?
    var onPlayingChanged: ((Bool) -> Void)?

    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var rateObservation: NSKeyValueObservation?

    init() {
        player.actionAtItemEnd = .pause
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.4, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            let current = time.seconds.isFinite ? time.seconds : 0
            let itemDuration = self.player.currentItem?.duration.seconds ?? 0
            let duration = (itemDuration.isFinite && itemDuration > 0) ? itemDuration : 0
            self.onTick?(current, duration)
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.onEnded?() }
        rateObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            self?.onPlayingChanged?(player.timeControlStatus == .playing)
        }
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        rateObservation?.invalidate()
        statusObservation?.invalidate()
    }

    func load(url: URL, autoplay: Bool) {
        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = 5
        player.replaceCurrentItem(with: item)
        if autoplay { player.play() }
    }

    func play() { player.play() }
    func pause() { player.pause() }

    func seek(_ seconds: Double) {
        guard seconds.isFinite, seconds >= 0 else { return }
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func setRate(_ rate: Float) {
        if #available(iOS 16.0, *) {
            player.defaultRate = rate
        }
        if player.timeControlStatus == .playing { player.rate = rate }
    }

    var isPlaying: Bool { player.timeControlStatus == .playing }
}
