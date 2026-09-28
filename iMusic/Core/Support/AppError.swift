import Foundation

enum AppError: LocalizedError, Equatable {
    case offline
    case network
    case timeout
    case rateLimited
    case server(Int)
    case parsing
    case unavailable
    case stream
    case cancelled

    var errorDescription: String? {
        switch self {
        case .offline: return String(localized: "Tidak ada koneksi internet.")
        case .network: return String(localized: "Gagal terhubung ke jaringan.")
        case .timeout: return String(localized: "Koneksi lambat. Coba lagi.")
        case .rateLimited: return String(localized: "Server sedang sibuk. Coba lagi nanti.")
        case .server(let code): return String(localized: "Server bermasalah (\(code)).")
        case .parsing: return String(localized: "Respons tidak dikenali.")
        case .unavailable: return String(localized: "Lagu ini tidak tersedia.")
        case .stream: return String(localized: "Tidak bisa memutar lagu ini.")
        case .cancelled: return nil
        }
    }
}

extension Error {
    var asAppError: AppError {
        if let e = self as? AppError { return e }
        let ns = self as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
                return .offline
            case NSURLErrorTimedOut:
                return .timeout
            case NSURLErrorCancelled:
                return .cancelled
            default:
                return .network
            }
        }
        return .network
    }
}
