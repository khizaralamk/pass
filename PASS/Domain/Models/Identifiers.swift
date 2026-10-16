import Foundation

/// Type-safe string identifiers. The backend phase keeps the raw string (UUIDs from Supabase/Firestore fit without changes).
struct ID<Tag>: Hashable, Codable, Sendable, CustomStringConvertible, ExpressibleByStringLiteral {
    let raw: String
    init(_ raw: String) { self.raw = raw }
    init(stringLiteral value: String) { self.raw = value }
    static func new() -> ID<Tag> { ID(UUID().uuidString.lowercased()) }
    var description: String { raw }

    init(from decoder: Decoder) throws { raw = try decoder.singleValueContainer().decode(String.self) }
    func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(raw) }
}

enum UserTag {}
enum GroupTag {}
enum RelayTag {}
enum ChallengeTag {}
enum SubmissionTag {}
enum ReportTag {}

typealias UserID = ID<UserTag>
typealias GroupID = ID<GroupTag>
typealias RelayID = ID<RelayTag>
typealias ChallengeID = ID<ChallengeTag>
typealias SubmissionID = ID<SubmissionTag>
typealias ReportID = ID<ReportTag>
