import Foundation

enum AppConfig {
    /// Content language / region sent to InnerTube.
    static var hl = "id"
    static var gl = "ID"

    static let userAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 " +
        "(KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1"

    /// Used for the `/player` call with the `IOS` client. A browser UA/Origin
    /// there is what pushes YouTube toward `signatureCipher`/throttling.
    static let iosUserAgent =
        "com.google.ios.youtube/19.09.3 (iPhone14,3; U; CPU iOS 16_0 like Mac OS X)"

    /// Audio itag preference: 140 = AAC 128 kbps, 139 = AAC 48 kbps.
    static let preferredAudioItags = [140, 139]
}
