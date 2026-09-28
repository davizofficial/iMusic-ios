import MediaPlayer
import UIKit

/// Lock-screen / Control Center metadata and remote commands.
enum NowPlayingCenter {
    private static var artworkCache: [String: MPMediaItemArtwork] = [:]
    private static var loadingArtwork: Set<String> = []

    static func update(song: Song, time: Double, duration: Double, rate: Double) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyArtist: song.artist,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: time,
            MPNowPlayingInfoPropertyPlaybackRate: rate,
        ]
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if let art = artworkCache[song.videoId] {
            info[MPMediaItemPropertyArtwork] = art
        } else if let urlString = URL(string: song.thumbnail) {
            info[MPMediaItemPropertyArtwork] = placeholderArtwork()
            loadArtwork(from: urlString, videoId: song.videoId)
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    static func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    static func installCommands(
        play: @escaping () -> Void,
        pause: @escaping () -> Void,
        toggle: @escaping () -> Void,
        next: @escaping () -> Void,
        previous: @escaping () -> Void,
        seek: @escaping (Double) -> Void
    ) {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.playCommand.addTarget { _ in play(); return .success }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { _ in pause(); return .success }

        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { _ in toggle(); return .success }

        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { _ in next(); return .success }

        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { _ in previous(); return .success }

        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            seek(e.positionTime)
            return .success
        }
    }

    // MARK: Artwork

    private static func placeholderArtwork() -> MPMediaItemArtwork {
        let size = CGSize(width: 544, height: 544)
        return MPMediaItemArtwork(boundsSize: size) { _ in
            UIGraphicsImageRenderer(size: size).image { ctx in
                UIColor(white: 0.12, alpha: 1).setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
            }
        }
    }

    private static func loadArtwork(from url: URL, videoId: String) {
        guard !loadingArtwork.contains(videoId) else { return }
        loadingArtwork.insert(videoId)
        URLSession.shared.dataTask(with: url) { data, _, _ in
            defer { DispatchQueue.main.async { loadingArtwork.remove(videoId) } }
            guard let data, let image = UIImage(data: data) else { return }
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            DispatchQueue.main.async {
                artworkCache[videoId] = artwork
                if var info = MPNowPlayingInfoCenter.default().nowPlayingInfo {
                    info[MPMediaItemPropertyArtwork] = artwork
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
                }
            }
        }.resume()
    }
}
