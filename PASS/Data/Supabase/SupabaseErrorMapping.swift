import Foundation
import Supabase

/// Turns SDK errors into the single user-facing `AppError`. Business-rule failures arrive from PostgREST as SQLSTATE
/// `P0001` with the contract's snake_case code in `message` and the user-safe text in `details`
/// (`backend/docs/01-API-CONTRACT.md`, "Error").
enum SupabaseErrorMapping {
    static func map(_ error: Error) -> AppError {
        if let app = error as? AppError { return app }
        if error is CancellationError { return .cancelled }
        if let url = error as? URLError { return url.code == .cancelled ? .cancelled : .network }
        if let pg = error as? PostgrestError { return map(code: pg.code, message: pg.message, details: pg.details) }
        if let fn = error as? FunctionsError {
            switch fn {
            case .relayError: return .network
            case .httpError(let status, let data): return map(functionStatus: status, body: data)
            }
        }
        if let auth = error as? AuthError {
            switch auth {
            case .sessionMissing:
                return .unauthorized
            case .api(let message, let errorCode, _, let response):
                if response.statusCode == 401 || errorCode == .sessionNotFound || errorCode == .sessionExpired { return .unauthorized }
                return .unknown(message)
            default:
                return .unknown(auth.localizedDescription)
            }
        }
        if let storage = error as? StorageError {
            switch storage.statusCode {
            case "401": return .unauthorized
            case "403": return .permissionDenied("You can't upload to this Relay right now.")
            case "413": return .media("That file is too large to upload.")
            default: return .media("Couldn't upload your capture. Please try again.")
            }
        }
        return AppError.wrap(error)
    }

    /// Pure mapping of a PostgREST error triple. `P0001` carries a contract code; other SQLSTATEs are infrastructure.
    static func map(code: String?, message: String, details: String?) -> AppError {
        switch code {
        case "P0001":
            return map(contractCode: message.trimmingCharacters(in: .whitespacesAndNewlines), text: details)
        case "PGRST301", "PGRST302", "PGRST303":   // JWT missing/expired/invalid
            return .unauthorized
        case "42501":                              // insufficient_privilege (RLS)
            return .permissionDenied("You don't have access to that.")
        case "PGRST116":                           // single row expected, none found
            return .notFound("That")
        case "23505":                              // unique_violation
            return .conflict("That already exists.")
        default:
            return .unknown(message)
        }
    }

    /// The contract's error codes. `text` is the server's user-safe DETAIL; the fallbacks mirror spec copy.
    static func map(contractCode code: String, text: String?) -> AppError {
        let t = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let copy = (t?.isEmpty == false) ? t : nil
        switch code {
        case "unauthorized": return .unauthorized
        case "not_found": return .notFound(copy ?? "That")
        case "onboarding_required": return .permissionDenied(copy ?? "Finish setting up your profile first.")
        case "group_too_small": return .conflict(copy ?? "You need at least 3 members to start a Relay.")
        case "group_full": return .conflict(copy ?? "This group is full (7 members max).")
        case "relay_already_active": return .conflict(copy ?? "This group already has an active Relay.")
        case "not_holder": return .permissionDenied(copy ?? "It isn't your turn with the Baton.")
        case "already_submitted": return .conflict(copy ?? "You've already submitted for this Relay.")
        case "must_submit_first": return .conflict(copy ?? "Submit your photo or video before passing the Baton.")
        case "not_eligible": return .conflict(copy ?? "That member can't take the Baton right now.")
        case "relay_not_active": return .conflict(copy ?? "This Relay has ended.")
        case "deadline_passed": return .conflict(copy ?? "The Baton window has closed.")
        case "blocked": return .permissionDenied(copy ?? "You can't join this group.")
        case "forbidden": return .permissionDenied(copy ?? "You don't have access to that.")
        case "validation": return .validation(copy ?? "Please check what you entered.")
        default: return .unknown(copy ?? code)
        }
    }

    /// Edge Functions return the same `{ code, message }` body on failure.
    static func map(functionStatus status: Int, body: Data) -> AppError {
        struct Body: Decodable { var code: String?; var message: String? }
        if let decoded = try? JSONDecoder().decode(Body.self, from: body), let code = decoded.code {
            return map(contractCode: code, text: decoded.message)
        }
        return map(status: status)
    }

    static func map(status: Int) -> AppError {
        switch status {
        case 401: return .unauthorized
        case 403: return .permissionDenied("You don't have access to that.")
        case 404: return .notFound("That")
        case 408, 502, 503, 504: return .network
        default: return .unknown("HTTP \(status)")
        }
    }
}

/// Server enum keys for `reports.reason` (the DB enum uses short keys, not the Swift raw values shown in the UI).
extension ReportReason {
    var serverKey: String {
        switch self {
        case .harassment: return "harassment"
        case .nudity: return "nudity"
        case .violence: return "violence"
        case .spam: return "spam"
        case .other: return "other"
        }
    }
}
