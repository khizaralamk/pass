import Foundation
import Testing
@testable import PASS

/// Scenario tests for the game rules (spec §9–§17). Time is simulated, so a full day of events runs in milliseconds.
struct RelayEngineTests {
    let rules = RelayRules.standard
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func member(_ id: String, daysAgo: Double) -> GroupMember {
        GroupMember(user: UserSummary(id: UserID(id), displayName: id.capitalized, colorHex: "#FF6B35"), role: id == "a" ? .creator : .member,
                    joinedAt: t0.addingTimeInterval(-daysAgo * 86_400))
    }

    func group(_ ids: [String]) -> Group {
        Group(id: "g", name: "Crew", emoji: "🌙", inviteCode: "PASS-AB12", createdBy: "a", createdAt: t0.addingTimeInterval(-10 * 86_400),
              members: ids.enumerated().map { member($0.element, daysAgo: Double(10 - $0.offset)) }, stats: GroupStats())
    }

    func start(_ ids: [String] = ["a", "b", "c", "d", "e"]) throws -> Relay {
        try RelayEngine.start(group: group(ids), challengeTitle: "Worst selfie wins", creator: "a", hasActiveRelay: false, now: t0, rules: rules)
    }

    func submit(_ r: Relay, _ id: String, at: Date) throws -> Relay {
        try RelayEngine.submit(r, by: UserID(id), mediaType: .photo, fileName: "\(id).jpg", durationMs: nil, now: at, rules: rules).0
    }

    // MARK: Start

    @Test func creatorHoldsBatonWithTwoHourDeadline() throws {
        let r = try start()
        #expect(r.isHolder("a"))
        #expect(r.currentTurn?.deadline == t0.addingTimeInterval(2 * 3600))
        #expect(r.participants.count == 5)
        #expect(r.status == .active)
    }

    @Test func startRequiresThreeMembers() {
        #expect(throws: RelayEngineError.groupTooSmall(needed: 1)) {
            try RelayEngine.start(group: group(["a", "b"]), challengeTitle: "x", creator: "a", hasActiveRelay: false, now: t0, rules: rules)
        }
    }

    @Test func startRefusesSecondActiveRelay() {
        #expect(throws: RelayEngineError.groupHasActiveRelay) {
            try RelayEngine.start(group: group(["a", "b", "c"]), challengeTitle: "x", creator: "a", hasActiveRelay: true, now: t0, rules: rules)
        }
    }

    // MARK: Submit & pass

    @Test func onlyHolderCanSubmitAndMustSubmitBeforePassing() throws {
        let r = try start()
        #expect(throws: RelayEngineError.notHolder) { _ = try submit(r, "b", at: t0) }
        #expect(throws: RelayEngineError.mustSubmitFirst) { _ = try RelayEngine.pass(r, from: "a", to: "b", now: t0, rules: rules) }
    }

    @Test func holderKeepsBatonAfterSubmittingUntilTheyPass() throws {
        var r = try start()
        r = try submit(r, "a", at: t0.addingTimeInterval(60))
        #expect(r.isHolder("a"))
        #expect(r.hasSubmitted("a"))
        #expect(RelayEngine.eligibleNext(r, excluding: "a").map(\.id.raw) == ["b", "c", "d", "e"])
        let (after, events) = try RelayEngine.pass(r, from: "a", to: "c", now: t0.addingTimeInterval(120), rules: rules)
        #expect(after.isHolder("c"))
        #expect(after.currentTurn?.deadline == t0.addingTimeInterval(120 + 2 * 3600))
        #expect(events == [.batonReceived(to: "c", from: "a")])
        #expect(after.turns.filter(\.isOpen).count == 1, "exactly one open turn at any time")
    }

    @Test func cannotPassToSomeoneWhoAlreadyWent() throws {
        var r = try start(["a", "b", "c"])
        r = try submit(r, "a", at: t0)
        r = try RelayEngine.pass(r, from: "a", to: "b", now: t0, rules: rules).0
        r = try submit(r, "b", at: t0)
        #expect(throws: RelayEngineError.notEligible) { _ = try RelayEngine.pass(r, from: "b", to: "a", now: t0, rules: rules) }
    }

    @Test func happyPathCompletesWithEveryoneAndRevealOrder() throws {
        var r = try start(["a", "b", "c"])
        var t = t0
        r = try submit(r, "a", at: t)
        t += 60; r = try RelayEngine.pass(r, from: "a", to: "c", now: t, rules: rules).0
        t += 60; r = try submit(r, "c", at: t)
        t += 60; r = try RelayEngine.pass(r, from: "c", to: "b", now: t, rules: rules).0
        t += 60
        let (final, events) = try RelayEngine.submit(r, by: "b", mediaType: .video, fileName: "b.mov", durationMs: 3000, now: t, rules: rules)
        #expect(final.status == .complete)
        #expect(final.outcome == .complete)
        #expect(events.contains(.ended(.complete)))
        #expect(final.submissionsInOrder.map(\.userID.raw) == ["a", "c", "b"], "Reveal order is Baton order, not join order")
        #expect(final.currentTurn == nil)
        let manifest = RevealManifest.make(from: final)
        #expect(manifest?.items.map(\.firstName) == ["A", "C", "B"])
    }

    @Test func onePersonLeftEventFiresOnPenultimateSubmission() throws {
        var r = try start(["a", "b", "c"])
        r = try submit(r, "a", at: t0)
        r = try RelayEngine.pass(r, from: "a", to: "b", now: t0, rules: rules).0
        let (_, events) = try RelayEngine.submit(r, by: "b", mediaType: .photo, fileName: "b.jpg", durationMs: nil, now: t0, rules: rules)
        #expect(events.contains(.onePersonLeft))
    }

    // MARK: Expiry, deferral, rescue (§11)

    @Test func firstMissDefersAndMovesToEarliestWaitingMember() throws {
        var r = try start()
        r = try submit(r, "a", at: t0)
        r = try RelayEngine.pass(r, from: "a", to: "d", now: t0, rules: rules).0
        let expiry = t0.addingTimeInterval(2 * 3600)
        let (after, events) = RelayEngine.processDeadlines(r, now: expiry.addingTimeInterval(5), rules: rules)
        #expect(after.participant("d")?.state == .deferred)
        #expect(after.participant("d")?.dropCount == 1)
        #expect(after.isHolder("b"), "earliest-joined waiting member gets the Baton (OPEN-1)")
        #expect(after.currentTurn?.startedAt == expiry, "the new turn starts when the old one expired, like a server job")
        #expect(events == [.deferred("d"), .batonReceived(to: "b", from: "d")])
    }

    @Test func deferredMemberIsNotOfferedWhileOthersWait() throws {
        var r = try start(["a", "b", "c", "d"])
        r = try submit(r, "a", at: t0)
        r = try RelayEngine.pass(r, from: "a", to: "b", now: t0, rules: rules).0
        r = RelayEngine.processDeadlines(r, now: t0.addingTimeInterval(3 * 3600), rules: rules).0 // b drops → c holds
        #expect(r.isHolder("c"))
        r = try submit(r, "c", at: t0.addingTimeInterval(3 * 3600 + 10))
        #expect(RelayEngine.eligibleNext(r, excluding: "c").map(\.id.raw) == ["d"], "b is deferred, so only d is offered")
    }

    @Test func rescueStartsAutomaticallyWhenOnlyDeferredRemainAndSucceeds() throws {
        var r = try start(["a", "b", "c"])
        r = try submit(r, "a", at: t0)
        r = try RelayEngine.pass(r, from: "a", to: "b", now: t0, rules: rules).0
        let drop = t0.addingTimeInterval(2 * 3600)
        var events: [RelayEvent]
        (r, events) = RelayEngine.processDeadlines(r, now: drop, rules: rules)   // b drops, c gets the Baton
        #expect(r.isHolder("c"))
        (r, events) = try RelayEngine.submit(r, by: "c", mediaType: .photo, fileName: "c.jpg", durationMs: nil, now: drop.addingTimeInterval(60), rules: rules)
        #expect(r.isHolder("b"), "no one else waiting → rescue for the deferred member starts immediately")
        #expect(r.currentTurn?.isRescue == true)
        #expect(r.currentTurn?.deadline == drop.addingTimeInterval(60 + 15 * 60))
        #expect(events.contains(.rescueStarted("b")))
        let (final, endEvents) = try RelayEngine.submit(r, by: "b", mediaType: .photo, fileName: "b.jpg", durationMs: nil, now: drop.addingTimeInterval(120), rules: rules)
        #expect(final.outcome == .complete, "a rescued relay still counts as complete")
        #expect(endEvents.contains(.ended(.complete)))
    }

    @Test func secondMissExcludesAndThreeSubmissionsStillGiveAReveal() throws {
        var r = try start(["a", "b", "c", "d"])
        r = try submit(r, "a", at: t0)
        r = try RelayEngine.pass(r, from: "a", to: "b", now: t0, rules: rules).0
        var t = t0.addingTimeInterval(2 * 3600)
        r = RelayEngine.processDeadlines(r, now: t, rules: rules).0            // b deferred → c
        t += 60; r = try submit(r, "c", at: t)
        t += 60; r = try RelayEngine.pass(r, from: "c", to: "d", now: t, rules: rules).0
        t += 60; r = try submit(r, "d", at: t)                                  // only b left → rescue for b
        #expect(r.currentTurn?.isRescue == true && r.isHolder("b"))
        t += 15 * 60
        let (final, events) = RelayEngine.processDeadlines(r, now: t, rules: rules)
        #expect(final.participant("b")?.state == .excluded)
        #expect(final.status == .failed)
        #expect(final.outcome == .failedWithReveal, "3 of 4 submitted → Reveal with the successful three")
        #expect(events.contains(.excluded("b")) && events.contains(.ended(.failedWithReveal)))
        #expect(RevealManifest.make(from: final)?.items.count == 3)
        var stats = GroupStats(completedRelays: 5, currentStreak: 3)
        stats.apply(.failedWithReveal)
        #expect(stats == GroupStats(completedRelays: 5, currentStreak: 0), "not counted as completed; streak reset")
    }

    @Test func fewerThanThreeSubmissionsFailsWithoutReveal() throws {
        var r = try start(["a", "b", "c"])
        r = try submit(r, "a", at: t0)
        r = try RelayEngine.pass(r, from: "a", to: "b", now: t0, rules: rules).0
        // b drops (2 h) → c holds, c drops (2 h) → rescue b (15 min) misses → rescue c (15 min) misses
        let (final, _) = RelayEngine.processDeadlines(r, now: t0.addingTimeInterval(24 * 3600), rules: rules)
        #expect(final.status == .failed)
        #expect(final.outcome == .failed)
        #expect(final.hasReveal == false)
        #expect(RevealManifest.make(from: final) == nil)
        #expect(final.participants.filter { $0.state == .excluded }.count == 2)
    }

    @Test func rescueOrderIsFirstDroppedFirst() throws {
        var r = try start(["a", "b", "c", "d"])
        r = try submit(r, "a", at: t0)
        r = try RelayEngine.pass(r, from: "a", to: "c", now: t0, rules: rules).0
        var t = t0.addingTimeInterval(2 * 3600)
        r = RelayEngine.processDeadlines(r, now: t, rules: rules).0 // c drops → b
        t += 2 * 3600
        r = RelayEngine.processDeadlines(r, now: t, rules: rules).0 // b drops → d
        t += 60; r = try submit(r, "d", at: t)                      // → rescue
        #expect(r.isHolder("c"), "c dropped first, so c is rescued first")
    }

    @Test func submittedButNeverPassedMovesOnWithoutADrop() throws {
        var r = try start(["a", "b", "c"])
        r = try submit(r, "a", at: t0)
        let (after, events) = RelayEngine.processDeadlines(r, now: t0.addingTimeInterval(2 * 3600), rules: rules)
        #expect(after.hasSubmitted("a") && after.participant("a")?.dropCount == 0)
        #expect(after.isHolder("b"))
        #expect(events == [.batonReceived(to: "b", from: "a")])
    }

    @Test func processDeadlinesIsIdempotentBeforeExpiry() throws {
        let r = try start()
        let (same, events) = RelayEngine.processDeadlines(r, now: t0.addingTimeInterval(3600), rules: rules)
        #expect(same == r)
        #expect(events.isEmpty)
    }

    // MARK: Cancel (§17)

    @Test func cancelClearsMediaAndEndsRelay() throws {
        var r = try start(["a", "b", "c"])
        r = try submit(r, "a", at: t0)
        let (c, events) = RelayEngine.cancel(r, reason: "Relay ended because a member left the group.", now: t0)
        #expect(c.status == .cancelled && c.outcome == .cancelled)
        #expect(c.participants.allSatisfy { $0.submission == nil })
        #expect(c.currentTurn == nil)
        #expect(events == [.ended(.cancelled)])
        #expect(throws: RelayEngineError.notActive) { _ = try submit(c, "a", at: t0) }
    }
}

struct GroupStatsTests {
    @Test func successIncrementsBoth() {
        var s = GroupStats(completedRelays: 23, currentStreak: 7)
        s.apply(.complete)
        #expect(s == GroupStats(completedRelays: 24, currentStreak: 8))
    }

    @Test func anyFailureResetsStreakOnly() {
        for outcome in [RelayOutcome.failed, .failedWithReveal, .cancelled] {
            var s = GroupStats(completedRelays: 23, currentStreak: 7)
            s.apply(outcome)
            #expect(s == GroupStats(completedRelays: 23, currentStreak: 0))
        }
    }
}
