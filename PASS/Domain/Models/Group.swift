import Foundation

enum GroupRole: String, Codable, Sendable { case creator, member }

struct GroupMember: Identifiable, Hashable, Codable, Sendable {
    var user: UserSummary
    var role: GroupRole
    var joinedAt: Date
    var id: UserID { user.id }
}

/// Lifetime completed count and the current streak (spec §7). The streak is the prominent number.
struct GroupStats: Hashable, Codable, Sendable {
    var completedRelays: Int = 0
    var currentStreak: Int = 0

    mutating func apply(_ outcome: RelayOutcome) {
        switch outcome {
        case .complete:
            completedRelays += 1
            currentStreak += 1
        case .failedWithReveal, .failed, .cancelled:
            currentStreak = 0
        }
    }
}

struct Group: Identifiable, Hashable, Codable, Sendable {
    let id: GroupID
    var name: String
    var emoji: String
    var inviteCode: String
    var createdBy: UserID
    var createdAt: Date
    var members: [GroupMember]
    var stats: GroupStats

    var memberCount: Int { members.count }
    func isCreator(_ userID: UserID) -> Bool { createdBy == userID }
    func contains(_ userID: UserID) -> Bool { members.contains { $0.id == userID } }
    func member(_ userID: UserID) -> GroupMember? { members.first { $0.id == userID } }
    var membersByJoinOrder: [GroupMember] { members.sorted { $0.joinedAt < $1.joinedAt } }
}

/// What an invitee sees before joining (spec §3 "invitation restored"). No media, no stats beyond names.
struct InvitePreview: Hashable, Codable, Sendable {
    var group: Group
    var invitedBy: UserSummary
    var activeRelay: Relay?
}
