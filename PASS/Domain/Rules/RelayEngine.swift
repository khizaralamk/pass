import Foundation

/// Side effects the caller (mock store today, backend tomorrow) turns into notifications or UI.
enum RelayEvent: Equatable, Sendable {
    case batonReceived(to: UserID, from: UserID?)
    case deferred(UserID)
    case rescueStarted(UserID)
    case excluded(UserID)
    case onePersonLeft
    case ended(RelayOutcome)
}

enum RelayEngineError: Error, Equatable, Sendable {
    case notActive
    case notHolder
    case alreadySubmitted
    case mustSubmitFirst
    case notEligible
    case groupTooSmall(needed: Int)
    case groupHasActiveRelay
}

/// Pure game rules from spec §9–§17. No I/O, no SwiftUI, deterministic given `now`.
/// The mock store applies these locally; the backend phase re-implements the same rules server-side and this file stays
/// as the reference (and the test oracle) for the client.
enum RelayEngine {

    // MARK: Start (§8, §9)

    static func start(group: Group, challengeTitle: String, creator: UserID, hasActiveRelay: Bool, now: Date, rules: RelayRules) throws -> Relay {
        guard !hasActiveRelay else { throw RelayEngineError.groupHasActiveRelay }
        guard group.memberCount >= rules.minMembersToStart else {
            throw RelayEngineError.groupTooSmall(needed: rules.minMembersToStart - group.memberCount)
        }
        guard group.contains(creator) else { throw RelayEngineError.notEligible }
        let participants = group.membersByJoinOrder.map {
            RelayParticipant(user: $0.user, state: $0.id == creator ? .holding : .waiting, joinedGroupAt: $0.joinedAt)
        }
        let turn = BatonTurn(id: UUID().uuidString, holderID: creator, passedBy: nil, startedAt: now,
                             deadline: now.addingTimeInterval(rules.batonWindow), isRescue: false)
        return Relay(id: .new(), groupID: group.id, groupName: group.name, groupEmoji: group.emoji,
                     challengeTitle: challengeTitle, createdBy: creator, createdAt: now, status: .active,
                     outcome: nil, endedAt: nil, endedReason: nil, participants: participants, turns: [turn])
    }

    // MARK: Submit (§12)

    static func submit(_ relay: Relay, by userID: UserID, mediaType: MediaType, fileName: String, durationMs: Int?, now: Date, rules: RelayRules) throws -> (Relay, [RelayEvent]) {
        guard relay.isActive else { throw RelayEngineError.notActive }
        guard relay.isHolder(userID) else { throw RelayEngineError.notHolder }
        guard !relay.hasSubmitted(userID) else { throw RelayEngineError.alreadySubmitted }

        var r = relay
        let submission = Submission(id: .new(), userID: userID, mediaType: mediaType, fileName: fileName,
                                    durationMs: durationMs, submittedAt: now, position: r.submittedCount + 1)
        r.update(userID) { $0.submission = submission; $0.state = .submitted }

        var events: [RelayEvent] = []
        let remaining = r.participants.filter { !$0.hasSubmitted && $0.state != .excluded }
        if remaining.count == 1 { events.append(.onePersonLeft) }

        if !eligibleNext(r, excluding: userID).isEmpty {
            // The holder keeps the Baton until they choose who's next (§13). The turn stays open with its deadline.
            return (r, events)
        }
        // Nobody left to choose from: close the turn and let the engine rescue a deferred member or finish.
        closeCurrentTurn(&r, at: now)
        events += advance(&r, from: userID, at: now, rules: rules)
        return (r, events)
    }

    // MARK: Pass (§13)

    /// Members the holder may pass to: not submitted, not deferred, not excluded, not the holder (§13 + OPEN-5).
    static func eligibleNext(_ relay: Relay, excluding userID: UserID) -> [RelayParticipant] {
        relay.participants
            .filter { $0.id != userID && $0.state == .waiting }
            .sorted { $0.joinedGroupAt < $1.joinedGroupAt }
    }

    static func pass(_ relay: Relay, from: UserID, to: UserID, now: Date, rules: RelayRules) throws -> (Relay, [RelayEvent]) {
        guard relay.isActive else { throw RelayEngineError.notActive }
        guard relay.isHolder(from) else { throw RelayEngineError.notHolder }
        guard relay.hasSubmitted(from) else { throw RelayEngineError.mustSubmitFirst }
        guard eligibleNext(relay, excluding: from).contains(where: { $0.id == to }) else { throw RelayEngineError.notEligible }

        var r = relay
        closeCurrentTurn(&r, at: now)
        openTurn(&r, holder: to, passedBy: from, at: now, window: rules.batonWindow, isRescue: false)
        return (r, [.batonReceived(to: to, from: from)])
    }

    // MARK: Deadlines (§11)

    /// Applies every expiry up to `now`. Each new turn starts at the moment the previous one expired, exactly as a server
    /// job running on schedule would do, so advancing a clock by hours yields the same result as real time passing.
    static func processDeadlines(_ relay: Relay, now: Date, rules: RelayRules) -> (Relay, [RelayEvent]) {
        var r = relay
        var events: [RelayEvent] = []
        var guardCount = 0
        while r.isActive, let turn = r.currentTurn, turn.deadline <= now, guardCount < 64 {
            guardCount += 1
            let at = turn.deadline
            let holderID = turn.holderID
            guard let holder = r.participant(holderID) else { break }

            if holder.hasSubmitted {
                // OPEN-5: submitted but never chose the next person. Keep the submission and move on without a drop.
                closeCurrentTurn(&r, at: at)
                events += advance(&r, from: holderID, at: at, rules: rules)
            } else if turn.isRescue {
                r.update(holderID) { $0.state = .excluded }
                events.append(.excluded(holderID))
                closeCurrentTurn(&r, at: at)
                events += advance(&r, from: holderID, at: at, rules: rules)
            } else {
                r.update(holderID) { $0.state = .deferred; $0.dropCount += 1; $0.deferredAt = at }
                events.append(.deferred(holderID))
                closeCurrentTurn(&r, at: at)
                events += advance(&r, from: holderID, at: at, rules: rules)
            }
        }
        return (r, events)
    }

    // MARK: Cancel (§17)

    static func cancel(_ relay: Relay, reason: String, now: Date) -> (Relay, [RelayEvent]) {
        guard relay.isActive else { return (relay, []) }
        var r = relay
        closeCurrentTurn(&r, at: now)
        r.status = .cancelled
        r.outcome = .cancelled
        r.endedAt = now
        r.endedReason = reason
        // Media for a cancelled relay is removed (§17); the store deletes the files.
        for p in r.participants { r.update(p.id) { $0.submission = nil; if $0.state == .holding { $0.state = .waiting } } }
        return (r, [.ended(.cancelled)])
    }

    // MARK: Reveal eligibility

    static func outcome(for relay: Relay, rules: RelayRules) -> RelayOutcome {
        let excluded = relay.participants.contains { $0.state == .excluded }
        if !excluded && relay.participants.allSatisfy({ $0.hasSubmitted }) { return .complete }
        return relay.submittedCount >= rules.minSubmissionsForReveal ? .failedWithReveal : .failed
    }

    // MARK: Private helpers

    /// After a holder is done (submitted with no one to choose, dropped, excluded): give the Baton to the earliest-joined
    /// waiting member (OPEN-1), else rescue the earliest-deferred member (OPEN-4), else finish.
    private static func advance(_ r: inout Relay, from previous: UserID, at: Date, rules: RelayRules) -> [RelayEvent] {
        if let next = r.participants.filter({ $0.state == .waiting }).sorted(by: { $0.joinedGroupAt < $1.joinedGroupAt }).first {
            openTurn(&r, holder: next.id, passedBy: previous, at: at, window: rules.batonWindow, isRescue: false)
            return [.batonReceived(to: next.id, from: previous)]
        }
        if let rescuee = r.participants.filter({ $0.state == .deferred }).sorted(by: { ($0.deferredAt ?? .distantPast) < ($1.deferredAt ?? .distantPast) }).first {
            openTurn(&r, holder: rescuee.id, passedBy: previous, at: at, window: rules.rescueWindow, isRescue: true)
            return [.rescueStarted(rescuee.id)]
        }
        let outcome = outcome(for: r, rules: rules)
        r.status = outcome == .complete ? .complete : .failed
        r.outcome = outcome
        r.endedAt = at
        return [.ended(outcome)]
    }

    private static func openTurn(_ r: inout Relay, holder: UserID, passedBy: UserID?, at: Date, window: TimeInterval, isRescue: Bool) {
        r.turns.append(BatonTurn(id: UUID().uuidString, holderID: holder, passedBy: passedBy, startedAt: at,
                                 deadline: at.addingTimeInterval(window), isRescue: isRescue))
        r.update(holder) { $0.state = .holding }
    }

    private static func closeCurrentTurn(_ r: inout Relay, at: Date) {
        guard let i = r.turns.lastIndex(where: { $0.isOpen }) else { return }
        r.turns[i].endedAt = at
    }
}
