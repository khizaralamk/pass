import Foundation

enum RelayStatus: String, Codable, Sendable { case active, complete, failed, cancelled }

/// How a relay ended. `failedWithReveal` = someone was excluded but ≥ 3 people submitted (spec §11).
enum RelayOutcome: String, Codable, Sendable {
    case complete, failedWithReveal, failed, cancelled

    var hasReveal: Bool { self == .complete || self == .failedWithReveal }
}

enum ParticipantState: String, Codable, Sendable {
    case waiting, holding, submitted, deferred, excluded
}

enum MediaType: String, Codable, Sendable { case photo, video }

/// A locked-in contribution. The file lives locally in the mock phase; the backend phase stores a remote object key instead.
struct Submission: Identifiable, Hashable, Codable, Sendable {
    let id: SubmissionID
    var userID: UserID
    var mediaType: MediaType
    var fileName: String
    var durationMs: Int?
    var submittedAt: Date
    /// 1-based Baton order (spec §18: Reveal in chronological order).
    var position: Int
}

struct RelayParticipant: Identifiable, Hashable, Codable, Sendable {
    var user: UserSummary
    var state: ParticipantState
    var dropCount: Int = 0
    var deferredAt: Date?
    var submission: Submission?
    var joinedGroupAt: Date
    var id: UserID { user.id }
    var hasSubmitted: Bool { submission != nil }
}

/// One Baton holding period. Deadlines are absolute timestamps; the client only ever computes `deadline - now`.
struct BatonTurn: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var holderID: UserID
    var passedBy: UserID?
    var startedAt: Date
    var deadline: Date
    var isRescue: Bool
    var endedAt: Date?

    var isOpen: Bool { endedAt == nil }
}

struct Relay: Identifiable, Hashable, Codable, Sendable {
    let id: RelayID
    var groupID: GroupID
    var groupName: String
    var groupEmoji: String
    var challengeTitle: String
    var createdBy: UserID
    var createdAt: Date
    var status: RelayStatus
    var outcome: RelayOutcome?
    var endedAt: Date?
    var endedReason: String?
    /// Group members at relay start, in join order (OPEN-2 assumption).
    var participants: [RelayParticipant]
    var turns: [BatonTurn]

    // MARK: Derived

    var isActive: Bool { status == .active }
    var currentTurn: BatonTurn? { turns.last(where: { $0.isOpen }) }
    var holder: RelayParticipant? { currentTurn.flatMap { participant($0.holderID) } }
    var submittedCount: Int { participants.filter { $0.hasSubmitted }.count }
    var participantCount: Int { participants.count }
    var submissionsInOrder: [Submission] { participants.compactMap(\.submission).sorted { $0.position < $1.position } }
    var hasReveal: Bool { outcome?.hasReveal ?? false }

    func participant(_ id: UserID) -> RelayParticipant? { participants.first { $0.id == id } }
    func isHolder(_ id: UserID) -> Bool { currentTurn?.holderID == id }
    func hasSubmitted(_ id: UserID) -> Bool { participant(id)?.hasSubmitted ?? false }

    /// The person who handed the Baton to the current holder, if any.
    var passer: UserSummary? {
        guard let turn = currentTurn, let by = turn.passedBy else { return nil }
        return participant(by)?.user
    }

    /// Members shown in the Baton-order list: submitted first in order, then the holder, then the rest in join order.
    var orderedForProgress: [RelayParticipant] {
        let submitted = participants.filter { $0.hasSubmitted }.sorted { ($0.submission?.position ?? 0) < ($1.submission?.position ?? 0) }
        let holder = participants.filter { $0.state == .holding && !$0.hasSubmitted }
        let rest = participants.filter { !$0.hasSubmitted && $0.state != .holding }.sorted { $0.joinedGroupAt < $1.joinedGroupAt }
        return submitted + holder + rest
    }

    mutating func update(_ id: UserID, _ change: (inout RelayParticipant) -> Void) {
        guard let i = participants.firstIndex(where: { $0.id == id }) else { return }
        change(&participants[i])
    }
}
