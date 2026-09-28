import Foundation

/// Converts a YouTube video to MP3 through the same third-party service the web
/// app uses (loader.to), called directly from the app — no backend.
///
/// This is intentionally optional and less reliable than the native M4A path:
/// it depends on a third party that may rate-limit or change at any time.
enum MP3Converter {
    static func convert(videoId: String) async throws -> URL {
        guard var comps = URLComponents(string: "https://loader.to/ajax/download.php") else { throw AppError.stream }
        comps.queryItems = [
            URLQueryItem(name: "format", value: "mp3"),
            URLQueryItem(name: "url", value: "https://www.youtube.com/watch?v=\(videoId)"),
        ]
        guard let url = comps.url else { throw AppError.stream }
        var req = URLRequest(url: url)
        req.setValue(AppConfig.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("https://loader.to/", forHTTPHeaderField: "Referer")

        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              (obj["success"] as? Bool) == true,
              let progressUrl = obj["progress_url"] as? String else {
            throw AppError.stream
        }

        for _ in 0..<60 {
            try await Task.sleep(nanoseconds: 2_500_000_000)
            guard let pu = URL(string: progressUrl) else { throw AppError.stream }
            var preq = URLRequest(url: pu)
            preq.setValue(AppConfig.userAgent, forHTTPHeaderField: "User-Agent")
            guard let (pdata, presp) = try? await URLSession.shared.data(for: preq),
                  (presp as? HTTPURLResponse)?.statusCode == 200,
                  let pobj = try? JSONSerialization.jsonObject(with: pdata) as? [String: Any] else { continue }
            if (pobj["success"] as? Bool) == true,
               let dl = pobj["download_url"] as? String,
               let downloadURL = URL(string: dl) {
                return downloadURL
            }
        }
        throw AppError.timeout
    }
}
