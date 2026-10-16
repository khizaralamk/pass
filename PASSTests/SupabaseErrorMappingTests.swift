import Foundation
import Testing
@testable import PASS

/// The backend raises business-rule failures as SQLSTATE P0001 with the contract code as MESSAGE and the user-safe text
/// as DETAIL (backend/docs/01-API-CONTRACT.md). The client must map every documented code to an `AppError`.
struct SupabaseErrorMappingTests {
    @Test func p0001CodesMapToAppErrors() {
        #expect(SupabaseErrorMapping.map(code: "P0001", message: "unauthorized", details: nil) == .unauthorized)
        #expect(SupabaseErrorMapping.map(code: "P0001", message: "not_found", details: "Group") == .notFound("Group"))
        #expect(SupabaseErrorMapping.map(code: "P0001", message: "group_full", details: "This group is full.") == .conflict("This group is full."))
        #expect(SupabaseErrorMapping.map(code: "P0001", message: "blocked", details: nil) == .permissionDenied("You can't join this group."))
        #expect(SupabaseErrorMapping.map(code: "P0001", message: "validation", details: "Name must be 2–30 characters.") == .validation("Name must be 2–30 characters."))
        #expect(SupabaseErrorMapping.map(code: "P0001", message: "forbidden", details: nil) == .permissionDenied("You don't have access to that."))
    }

    @Test func everyContractCodeHasAMapping() {
        let codes = ["unauthorized", "not_found", "onboarding_required", "group_too_small", "group_full", "relay_already_active",
                     "not_holder", "already_submitted", "must_submit_first", "not_eligible", "relay_not_active", "deadline_passed",
                     "blocked", "forbidden", "validation"]
        for code in codes {
            let mapped = SupabaseErrorMapping.map(contractCode: code, text: nil)
            if case .unknown = mapped { Issue.record("\(code) fell through to .unknown") }
        }
    }

    @Test func serverDetailWinsOverFallbackCopy() {
        let mapped = SupabaseErrorMapping.map(code: "P0001", message: "deadline_passed", details: "Too late — the window closed.")
        #expect(mapped == .conflict("Too late — the window closed."))
        #expect(SupabaseErrorMapping.map(code: "P0001", message: "deadline_passed", details: "  ") == .conflict("The Baton window has closed."))
    }

    @Test func infrastructureCodesAndTransportErrors() {
        #expect(SupabaseErrorMapping.map(code: "PGRST301", message: "JWT expired", details: nil) == .unauthorized)
        #expect(SupabaseErrorMapping.map(code: "42501", message: "permission denied", details: nil) == .permissionDenied("You don't have access to that."))
        #expect(SupabaseErrorMapping.map(code: "XX000", message: "boom", details: nil) == .unknown("boom"))
        #expect(SupabaseErrorMapping.map(URLError(.notConnectedToInternet)) == .network)
        #expect(SupabaseErrorMapping.map(URLError(.cancelled)) == .cancelled)
        #expect(SupabaseErrorMapping.map(CancellationError()) == .cancelled)
        #expect(SupabaseErrorMapping.map(AppError.conflict("x")) == .conflict("x"))
        #expect(SupabaseErrorMapping.map(status: 401) == .unauthorized)
    }

    @Test func edgeFunctionErrorBodiesUseTheSameCodes() {
        let body = Data(#"{"code":"not_found","message":"Relay not found"}"#.utf8)
        #expect(SupabaseErrorMapping.map(functionStatus: 404, body: body) == .notFound("Relay not found"))
        #expect(SupabaseErrorMapping.map(functionStatus: 503, body: Data()) == .network)
    }

    @Test func reportReasonsUseTheServerEnumKeys() {
        #expect(ReportReason.allCases.map(\.serverKey) == ["harassment", "nudity", "violence", "spam", "other"])
    }
}
