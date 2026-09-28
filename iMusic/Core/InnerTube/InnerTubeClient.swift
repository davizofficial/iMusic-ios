import CryptoKit
import Foundation

enum ITClient {
    case webRemix
    case ios
}

/// Direct InnerTube client. No backend: the app talks to YouTube Music itself.
/// Native apps are not subject to browser CORS, which is the only reason the
/// web version needs `server.js`.
final class InnerTubeClient {
    static let shared = InnerTubeClient()

    private let session: URLSession
    private let base = "https://music.youtube.com/youtubei/v1"

    private init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        cfg.timeoutIntervalForResource = 30
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: cfg)
    }

    private func context(_ client: ITClient) -> [String: Any] {
        switch client {
        case .webRemix:
            return ["client": [
                "clientName": "WEB_REMIX",
                "clientVersion": "1.20240101.00.00",
                "hl": AppConfig.hl,
                "gl": AppConfig.gl,
            ]]
        case .ios:
            return ["client": [
                "clientName": "IOS",
                "clientVersion": "19.09.3",
                "deviceModel": "iPhone14,3",
                "osName": "iPhone",
                "osVersion": "16.0.0.0",
                "hl": AppConfig.hl,
                "gl": AppConfig.gl,
            ]]
        }
    }

    /// - Parameter ttl: when set, the response is cached for this many seconds
    ///   and served from cache (or from stale cache if the network fails).
    func post(_ endpoint: String,
              body: [String: Any] = [:],
              query: String = "",
              client: ITClient = .webRemix,
              ttl: TimeInterval? = nil) async throws -> [String: Any] {
        guard var comps = URLComponents(string: "\(base)/\(endpoint)") else { throw AppError.parsing }
        comps.queryItems = [URLQueryItem(name: "prettyPrint", value: "false")]
        var urlString = comps.url?.absoluteString ?? "\(base)/\(endpoint)?prettyPrint=false"
        urlString += query
        guard let url = URL(string: urlString) else { throw AppError.parsing }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        switch client {
        case .webRemix:
            req.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
            req.setValue("https://music.youtube.com/", forHTTPHeaderField: "Referer")
            req.setValue(AppConfig.userAgent, forHTTPHeaderField: "User-Agent")
        case .ios:
            req.setValue(AppConfig.iosUserAgent, forHTTPHeaderField: "User-Agent")
        }

        var payload = body
        payload["context"] = context(client)
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        var key: String?
        if ttl != nil {
            let k = cacheKey(endpoint: endpoint, client: client, query: query, payload: payload)
            key = k
            if let hit = InnerTubeCache.shared.get(k, allowExpired: false) { return hit }
        }

        do {
            let (data, http) = try await send(req)
            switch http.statusCode {
            case 200...299: break
            case 429: throw AppError.rateLimited
            default: throw AppError.server(http.statusCode)
            }
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw AppError.parsing
            }
            if let ttl, let key { InnerTubeCache.shared.set(key, obj, ttl: ttl) }
            return obj
        } catch {
            if error is CancellationError { throw error }
            // Offline fallback: serve the last good response, even if expired.
            if let key, let stale = InnerTubeCache.shared.get(key, allowExpired: true) { return stale }
            throw error
        }
    }

    private func cacheKey(endpoint: String,
                          client: ITClient,
                          query: String,
                          payload: [String: Any]) -> String {
        let bodyData = (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data()
        var hasher = SHA256()
        hasher.update(data: Data("\(endpoint)|\(client)|\(query)|".utf8))
        hasher.update(data: bodyData)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Retries transient failures (timeout / dropped connection / 429 / 5xx)
    /// with 0.5s then 1.5s backoff, per plan §4.1.
    private func send(_ req: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let delays: [UInt64] = [500_000_000, 1_500_000_000]
        var attempt = 0
        while true {
            do {
                let (data, response) = try await session.data(for: req)
                guard let http = response as? HTTPURLResponse else { throw AppError.network }
                let transient = http.statusCode == 429 || (500...599).contains(http.statusCode)
                if transient, attempt < delays.count {
                    try await Task.sleep(nanoseconds: delays[attempt])
                    attempt += 1
                    continue
                }
                return (data, http)
            } catch {
                if error is CancellationError { throw error }
                let app = error.asAppError
                if (app == .timeout || app == .network), attempt < delays.count {
                    try await Task.sleep(nanoseconds: delays[attempt])
                    attempt += 1
                    continue
                }
                throw error
            }
        }
    }
}
