import Foundation
import WebKit

/// A robust audio player engine that leverages the official YouTube IFrame Player API
/// inside a lightweight, invisible `WKWebView`.
///
/// This completely bypasses InnerTube bot detection, PO Token checks, 400 FAILED_PRECONDITION
/// errors, and signatureCipher decoding issues. It plays any official YouTube Music audio
/// stream instantly and reliably on iOS 15+.
@MainActor
final class YouTubeAudioBridge: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    static let shared = YouTubeAudioBridge()

    private(set) var webView: WKWebView!

    var onTick: ((Double, Double) -> Void)?
    var onStateChange: ((Bool) -> Void)?
    var onEnded: (() -> Void)?
    var onError: ((Int) -> Void)?

    private var isPlayerReady = false
    private var pendingVideoId: String?
    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0

    override init() {
        super.init()
        setupWebView()
    }

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let controller = WKUserContentController()
        controller.add(self, name: "audioBridge")
        config.userContentController = controller

        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        webView.navigationDelegate = self
        webView.isHidden = true
        webView.isOpaque = false
        webView.backgroundColor = .clear

        loadHTML()
    }

    private func loadHTML() {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
        * { margin:0; padding:0; }
        body { background:#000; overflow:hidden; }
        #player { width:100%; height:100%; }
        </style>
        </head>
        <body>
        <div id="player"></div>
        <script>
        var player = null;
        var isReady = false;
        var pendingId = null;

        function post(msg) {
            try {
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.audioBridge) {
                    window.webkit.messageHandlers.audioBridge.postMessage(msg);
                }
            } catch(e) {}
        }

        var tag = document.createElement('script');
        tag.src = "https://www.youtube.com/iframe_api";
        var firstScriptTag = document.getElementsByTagName('script')[0];
        firstScriptTag.parentNode.insertBefore(tag, firstScriptTag);

        function onYouTubeIframeAPIReady() {
            player = new YT.Player('player', {
                height: '100%',
                width: '100%',
                playerVars: {
                    'playsinline': 1,
                    'controls': 0,
                    'disablekb': 1,
                    'fs': 0,
                    'rel': 0,
                    'autoplay': 1,
                    'origin': 'https://www.youtube.com'
                },
                events: {
                    'onReady': onPlayerReady,
                    'onStateChange': onPlayerStateChange,
                    'onError': onPlayerError
                }
            });
        }

        function onPlayerReady(event) {
            isReady = true;
            post({ event: 'ready' });
            if (pendingId) {
                playVideo(pendingId);
                pendingId = null;
            }
        }

        function onPlayerStateChange(event) {
            var state = event.data;
            var cur = (player && player.getCurrentTime) ? player.getCurrentTime() : 0;
            var dur = (player && player.getDuration) ? player.getDuration() : 0;
            post({ event: 'stateChange', state: state, currentTime: cur, duration: dur });
        }

        function onPlayerError(event) {
            post({ event: 'error', code: event.data });
        }

        function playVideo(id) {
            if (!isReady || !player || !player.loadVideoById) {
                pendingId = id;
            } else {
                player.loadVideoById(id);
            }
        }

        function pauseVideo() {
            if (player && player.pauseVideo) player.pauseVideo();
        }

        function resumeVideo() {
            if (player && player.playVideo) player.playVideo();
        }

        function seekTo(sec) {
            if (player && player.seekTo) player.seekTo(sec, true);
        }

        function setPlaybackRate(rate) {
            if (player && player.setPlaybackRate) player.setPlaybackRate(rate);
        }

        setInterval(function() {
            if (player && player.getPlayerState && player.getPlayerState() === 1) {
                var cur = player.getCurrentTime ? player.getCurrentTime() : 0;
                var dur = player.getDuration ? player.getDuration() : 0;
                post({ event: 'tick', currentTime: cur, duration: dur });
            }
        }, 350);
        </script>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
    }

    // MARK: - Controls

    func play(videoId: String) {
        if isPlayerReady {
            webView.evaluateJavaScript("playVideo('\(videoId)');", completionHandler: nil)
        } else {
            pendingVideoId = videoId
        }
        isPlaying = true
        onStateChange?(true)
    }

    func pause() {
        webView.evaluateJavaScript("pauseVideo();", completionHandler: nil)
        isPlaying = false
        onStateChange?(false)
    }

    func resume() {
        webView.evaluateJavaScript("resumeVideo();", completionHandler: nil)
        isPlaying = true
        onStateChange?(true)
    }

    func seek(to seconds: Double) {
        currentTime = seconds
        webView.evaluateJavaScript("seekTo(\(seconds));", completionHandler: nil)
    }

    func setRate(_ rate: Float) {
        webView.evaluateJavaScript("setPlaybackRate(\(rate));", completionHandler: nil)
    }

    // MARK: - WKScriptMessageHandler

    nonisolated func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let dict = message.body as? [String: Any],
              let event = dict["event"] as? String else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            switch event {
            case "ready":
                self.isPlayerReady = true
                if let pending = self.pendingVideoId {
                    self.pendingVideoId = nil
                    self.play(videoId: pending)
                }

            case "stateChange":
                let state = (dict["state"] as? NSNumber)?.intValue ?? -1
                let cur = (dict["currentTime"] as? NSNumber)?.doubleValue ?? 0
                let dur = (dict["duration"] as? NSNumber)?.doubleValue ?? 0
                if cur > 0 { self.currentTime = cur }
                if dur > 0 { self.duration = dur }

                switch state {
                case 1: // playing
                    self.isPlaying = true
                    self.onStateChange?(true)
                case 2: // paused
                    self.isPlaying = false
                    self.onStateChange?(false)
                case 0: // ended
                    self.isPlaying = false
                    self.onStateChange?(false)
                    self.onEnded?()
                default:
                    break
                }

            case "tick":
                let cur = (dict["currentTime"] as? NSNumber)?.doubleValue ?? 0
                let dur = (dict["duration"] as? NSNumber)?.doubleValue ?? 0
                self.currentTime = cur
                self.duration = dur
                self.onTick?(cur, dur)

            case "error":
                let code = (dict["code"] as? NSNumber)?.intValue ?? 0
                self.onError?(code)

            default:
                break
            }
        }
    }
}
