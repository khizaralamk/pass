import Foundation

struct Challenge: Identifiable, Hashable, Codable, Sendable {
    let id: ChallengeID
    var title: String
    var isBuiltIn: Bool
}
