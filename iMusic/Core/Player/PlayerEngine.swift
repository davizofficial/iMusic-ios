import AVFoundation
import Foundation

enum PlaybackMode {
    case local
    case youtube
}

/// Hybrid playback engine supporting both native local file playback (`AVPlayer`)
/// for offline downloaded tracks and official YouTube audio streaming (`YouTubeAudioBridge`)
/// for instant, unblocked online music.
@MainActor
final class PlayerEngine {
    private let player = AVPlayer()
    private let bridge = YouTubeAudioBridge.shared
    private var mode: PlaybackMode = .youtube

    var onTick: ((Double, Double) -> Void)?
    var onEnded: (() -> Void)?
    var onPlayingChanged: ((Bool) -> Void)?
    var onError: ((String) -> Void)?

    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var rateObservation: NSKeyValueObservation?

    init() {
        player.actionAtItemEnd = .pause
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.4, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            let current = time.seconds.isFinite ? time.seconds : 0
            Task { @MainActor [weak self] in
                guard let self, self.mode == .local else { return }
                let itemDuration = self.player.currentItem?.duration.seconds ?? 0
                let duration = (itemDuration.isFinite && itemDuration > 0) ? itemDuration : 0
                self.onTick?(current, duration)
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.mode == .local else { return }
                self.onEnded?()
            }
        }
        rateObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let isPlaying = player.timeControlStatus == .playing
            Task { @MainActor [weak self] in
                guard let self, self.mode == .local else { return }
                self.onPlayingChanged?(isPlaying)
            }
        }

        // Connect YouTube Bridge callbacks
        bridge.onTick = { [weak self] cur, dur in
            guard let self, self.mode == .youtube else { return }
            self.onTick?(cur, dur)
        }
        bridge.onStateChange = { [weak self] playing in
            guard let self, self.mode == .youtube else { return }
            self.onPlayingChanged?(playing)
        }
        bridge.onEnded = { [weak self] in
            guard let self, self.mode == .youtube else { return }
            self.onEnded?()
        }
        bridge.onError = { [weak self] code in
            guard let self, self.mode == .youtube else { return }
            self.onError?("YouTube Player Error (\(code))")
        }
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        rateObservation?.invalidate()
    }

    func loadLocal(url: URL, autoplay: Bool) {
        mode = .local
        bridge.pause()
        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = 5
        player.replaceCurrentItem(with: item)
        if autoplay { player.play() }
    }

    func loadYouTube(videoId: String, autoplay: Bool) {
        mode = .youtube
        player.pause()
        player.replaceCurrentItem(with: nil)
        bridge.play(videoId: videoId)
        if !autoplay {
            bridge.pause()
        }
    }

    func play() {
        if mode == .youtube {
            bridge.resume()
        } else {
            player.play()
        }
    }

    func pause() {
        if mode == .youtube {
            bridge.pause()
        } else {
            player.pause()
        }
    }

    func seek(_ seconds: Double) {
        guard seconds.isFinite, seconds >= 0 else { return }
        if mode == .youtube {
            bridge.seek(to: seconds)
        } else {
            player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600),
                        toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    func setRate(_ rate: Float) {
        bridge.setRate(rate)
        if #available(iOS 16.0, *) {
            player.defaultRate = rate
        }
        if player.timeControlStatus == .playing { player.rate = rate }
    }

    var isPlaying: Bool {
        mode == .youtube ? bridge.isPlaying : (player.timeControlStatus == .playing)
    }
}
