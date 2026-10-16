import Foundation

/// The single user-facing error type. Expected failures carry a message that is safe to show; unexpected ones are wrapped
/// so the UI never shows internals. The backend phase maps SDK errors into these cases.
enum AppError: Error, Equatable, LocalizedError, Sendable {
    case network
    case notFound(String)
    case unauthorized
    case validation(String)
    case conflict(String)
    case permissionDenied(String)
    case media(String)
    case cancelled
    case unknown(String)

    var errorDescription: String? { userMessage }

    /// Short, actionable copy for alerts and inline messages.
    var userMessage: String {
        switch self {
        case .network: return "Can't reach PASS right now. Check your connection and try again."
        case .notFound(let what): return "\(what) couldn't be found."
        case .unauthorized: return "Please sign in again."
        case .validation(let m), .conflict(let m), .permissionDenied(let m), .media(let m): return m
        case .cancelled: return "Cancelled."
        case .unknown: return "Something went wrong. Please try again."
        }
    }

    /// Cancellation is not a failure to present (BUILD rule: handle cancellation without showing it as an error).
    var isCancellation: Bool { if case .cancelled = self { return true } else { return false } }

    /// Converts any thrown error into an `AppError`, treating Swift cancellation as `.cancelled`.
    static func wrap(_ error: Error) -> AppError {
        if let app = error as? AppError { return app }
        if error is CancellationError { return .cancelled }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain { return .network }
        return .unknown(ns.localizedDescription)
    }
}

/// Load state for screens that fetch data. Every async path must end in `.loaded` or `.failed`, never stuck in `.loading`.
enum Loadable<Value: Equatable>: Equatable {
    case idle
    case loading
    case loaded(Value)
    case failed(AppError)

    var value: Value? { if case .loaded(let v) = self { return v } else { return nil } }
    var isLoading: Bool { if case .loading = self { return true } else { return false } }
    var error: AppError? { if case .failed(let e) = self { return e } else { return nil } }
}
