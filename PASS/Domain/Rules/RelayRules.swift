import Foundation

/// Game constants fixed by the spec (§5, §10, §11, §12). Stored in one place so a backend `app_config` can replace them later.
struct RelayRules: Hashable, Sendable {
    var batonWindow: TimeInterval
    var rescueWindow: TimeInterval
    var minMembersToStart: Int
    var maxMembers: Int
    var minSubmissionsForReveal: Int
    var maxVideoSeconds: Double
    var minimumAge: Int

    static let standard = RelayRules(
        batonWindow: 2 * 60 * 60,
        rescueWindow: 15 * 60,
        minMembersToStart: 3,
        maxMembers: 7,
        minSubmissionsForReveal: 3,
        maxVideoSeconds: 4,
        minimumAge: 16)

    /// Short windows for demos and tests (watch a drop and a rescue in one sitting).
    static let demo = RelayRules(
        batonWindow: 3 * 60,
        rescueWindow: 60,
        minMembersToStart: 3,
        maxMembers: 7,
        minSubmissionsForReveal: 3,
        maxVideoSeconds: 4,
        minimumAge: 16)
}
