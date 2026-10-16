import Foundation

/// All Reveal timing constants in one place (spec §19 + Figma `buildRevealSlides`). Bump `version` when the look changes
/// so cached exports are rebuilt.
struct RevealTemplate: Hashable, Sendable {
    var version = 1
    var intro: TimeInterval = 2.0          // spec 1–2 s (Figma 2.2 s): C4
    var photo: TimeInterval = 1.6          // spec 1.5–1.8 s
    var maxVideo: TimeInterval = 4.0       // spec §12
    var recap: TimeInterval = 1.8
    var passed: TimeInterval = 2.2
    var end: TimeInterval = 2.4
    var fade: TimeInterval = 0.35          // spec 0.25–0.4 s, fade from black at each segment start
    var nameDelay: TimeInterval = 0.15
    var nameDuration: TimeInterval = 0.4
    var nameFadeOutAt: TimeInterval = 1.6  // on segments longer than 2 s the name block fades (spec §19: not permanent)
    var fps: Int32 = 30
    var width = 1080
    var height = 1920

    static let standard = RevealTemplate()
}

/// Everything the Reveal needs, derived from a finished relay. Only successful submissions, in Baton order.
struct RevealManifest: Hashable, Sendable {
    struct Item: Hashable, Sendable, Identifiable {
        var position: Int
        var firstName: String
        var colorHex: String
        var mediaType: MediaType
        var fileName: String
        var durationMs: Int?
        var id: Int { position }
    }

    var relayID: RelayID
    var challengeTitle: String
    var groupName: String
    var outcome: RelayOutcome
    var participantCount: Int
    var items: [Item]

    var passedCount: Int { items.count }

    /// `nil` when the relay has no Reveal (active, cancelled, or fewer than 3 submissions).
    static func make(from relay: Relay) -> RevealManifest? {
        guard let outcome = relay.outcome, outcome.hasReveal else { return nil }
        let items = relay.submissionsInOrder.compactMap { s -> Item? in
            guard let p = relay.participant(s.userID) else { return nil }
            return Item(position: s.position, firstName: p.user.firstName, colorHex: p.user.colorHex,
                        mediaType: s.mediaType, fileName: s.fileName, durationMs: s.durationMs)
        }
        guard !items.isEmpty else { return nil }
        return RevealManifest(relayID: relay.id, challengeTitle: relay.challengeTitle, groupName: relay.groupName,
                              outcome: outcome, participantCount: relay.participantCount, items: items)
    }
}

enum RevealSegmentKind: Hashable, Sendable {
    case intro
    case participant(index: Int)
    case recap
    case passed
    case end
}

struct RevealSegment: Hashable, Sendable, Identifiable {
    var kind: RevealSegmentKind
    var start: TimeInterval
    var duration: TimeInterval
    var end: TimeInterval { start + duration }
    var id: RevealSegmentKind { kind }
}

/// Deterministic sequence (spec §18, §20): intro → participants in Baton order → recap → X/Y PASSED → end card.
enum RevealTimeline {
    static func build(_ manifest: RevealManifest, template: RevealTemplate = .standard) -> [RevealSegment] {
        var segments: [RevealSegment] = []
        var t: TimeInterval = 0
        func add(_ kind: RevealSegmentKind, _ d: TimeInterval) {
            segments.append(RevealSegment(kind: kind, start: t, duration: d))
            t += d
        }
        add(.intro, template.intro)
        for (i, item) in manifest.items.enumerated() {
            switch item.mediaType {
            case .photo: add(.participant(index: i), template.photo)
            case .video:
                let seconds = Double(item.durationMs ?? Int(template.maxVideo * 1000)) / 1000
                add(.participant(index: i), min(max(seconds, 0.5), template.maxVideo))
            }
        }
        add(.recap, template.recap)
        add(.passed, template.passed)
        add(.end, template.end)
        return segments
    }

    static func totalDuration(_ segments: [RevealSegment]) -> TimeInterval { segments.last?.end ?? 0 }

    static func segment(at time: TimeInterval, in segments: [RevealSegment]) -> RevealSegment? {
        segments.last { $0.start <= time } ?? segments.first
    }
}
