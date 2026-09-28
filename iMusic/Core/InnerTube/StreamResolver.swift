import Foundation

struct StreamInfo {
    var url: URL
    var mimeType: String
    var bitrate: Int
    var itag: Int
}

/// Resolves a playable audio URL via the InnerTube `/player` endpoint using the
/// iOS client, which normally returns plain `url`s for AAC audio (itag 140/139).
///
/// This is the single most fragile part of the app and the only piece not present
/// in `server.js`. Everything that can break lives here on purpose so the UI never
/// has to change when YouTube does.
enum StreamResolver {
    static func resolve(videoId: String) async throws -> StreamInfo {
        let d = try await InnerTubeClient.shared.post(
            "player",
            body: [
                "videoId": videoId,
                "contentCheckOk": true,
                "racyCheckOk": true,
            ],
            client: .ios
        )

        if let status = (d["playabilityStatus"] as? [String: Any])?["status"] as? String, status != "OK" {
            throw AppError.unavailable
        }
        guard let streaming = d["streamingData"] as? [String: Any] else { throw AppError.stream }

        let formats = (streaming["adaptiveFormats"] as? [[String: Any]]) ?? []
        let audio = formats.filter {
            guard let mime = $0["mimeType"] as? String else { return false }
            return mime.hasPrefix("audio/mp4") || mime.hasPrefix("audio/aac")
        }

        // Prefer known itags, then fall back to highest bitrate.
        let ordered = audio.sorted { a, b in
            let ia = (a["itag"] as? NSNumber)?.intValue ?? 0
            let ib = (b["itag"] as? NSNumber)?.intValue ?? 0
            let pa = AppConfig.preferredAudioItags.firstIndex(of: ia) ?? Int.max
            let pb = AppConfig.preferredAudioItags.firstIndex(of: ib) ?? Int.max
            if pa != pb { return pa < pb }
            let ba = (a["bitrate"] as? NSNumber)?.intValue ?? 0
            let bb = (b["bitrate"] as? NSNumber)?.intValue ?? 0
            return ba > bb
        }

        for f in ordered {
            if let urlStr = f["url"] as? String, let url = URL(string: urlStr) {
                return StreamInfo(
                    url: url,
                    mimeType: f["mimeType"] as? String ?? "audio/mp4",
                    bitrate: (f["bitrate"] as? NSNumber)?.intValue ?? 0,
                    itag: (f["itag"] as? NSNumber)?.intValue ?? 0
                )
            }
        }
        // signatureCipher / n-param throttling / PoToken required.
        throw AppError.stream
    }
}
