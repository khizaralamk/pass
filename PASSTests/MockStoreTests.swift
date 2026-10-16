import Foundation
import Testing
import UIKit
@testable import PASS

/// The mock backend behaves like the future server: it applies the engine, enforces group rules and emits events.
struct MockStoreTests {
    @MainActor
    func makeStore() async -> (MockDataStore, AdjustableDateProvider, LocalMediaStore) {
        let clock = AdjustableDateProvider()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pass-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let media = LocalMediaStore(directory: dir)
        let store = MockDataStore(clock: clock, media: media, rules: .standard, persistence: nil)
        await store.setLatency(.zero)
        await store.setCurrentUser(User(id: MockFixtures.meID, displayName: "Khizar", colorHex: "#6B46FF", avatarFileName: nil, memberSince: clock.now(), dateOfBirth: nil))
        return (store, clock, media)
    }

    @Test func fixturesSeedTwoGroupsAndOneActiveRelayForMe() async throws {
        let (store, _, _) = await makeStore()
        let groups = try await store.groups()
        #expect(groups.map(\.name) == ["Friday Night Crew", "Court Crew"])
        let relays = try await store.activeRelays()
        #expect(relays.count == 1)
        #expect(relays[0].isHolder(MockFixtures.meID))
        let history = try await store.history(groupID: MockFixtures.fridayID)
        #expect(history.count == 2 && history.allSatisfy { $0.hasReveal })
    }

    @Test func joinByCodeAddsMeAndRejectsFullGroups() async throws {
        let (store, _, _) = await makeStore()
        let preview = try await store.invitePreview(code: "pass-br22")
        #expect(preview.group.name == "Brunch Club" && preview.activeRelay != nil)
        let joined = try await store.joinGroup(code: "PASS-BR22")
        #expect(joined.contains(MockFixtures.meID))
        for _ in 0..<3 { _ = try await store.simulateJoin(groupID: joined.id) }
        #expect(try await store.group(joined.id).memberCount == 7)
        await #expect(throws: AppError.self) { _ = try await store.simulateJoin(groupID: joined.id) }
        await #expect(throws: AppError.self) { _ = try await store.invitePreview(code: "PASS-ZZZZ") }
    }

    @Test func startRelayNeedsThreeMembersAndOnlyOneActive() async throws {
        let (store, _, _) = await makeStore()
        let g = try await store.createGroup(name: "Tiny", emoji: "🐣")
        await #expect(throws: AppError.self) { _ = try await store.startRelay(groupID: g.id, challengeTitle: "x") }
        await #expect(throws: AppError.self) { _ = try await store.startRelay(groupID: MockFixtures.fridayID, challengeTitle: "x") }
        _ = try await store.simulateJoin(groupID: g.id)
        _ = try await store.simulateJoin(groupID: g.id)
        let r = try await store.startRelay(groupID: g.id, challengeTitle: "Find something red")
        #expect(r.isHolder(MockFixtures.meID) && r.participantCount == 3)
    }

    @Test func fullRelayThroughStoreUpdatesStatsAndEmitsEvents() async throws {
        let (store, _, media) = await makeStore()
        var events: [RelayEvent] = []
        let stream = await store.events()
        let collector = Task { for await e in stream { if case .relay(_, let evs) = e { events += evs } } }
        let g = try await store.createGroup(name: "Trio", emoji: "🎯")
        _ = try await store.simulateJoin(groupID: g.id)
        _ = try await store.simulateJoin(groupID: g.id)
        var r = try await store.startRelay(groupID: g.id, challengeTitle: "Show your view right now")
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).jpg")
        try UIImage(systemName: "star")!.jpegData(compressionQuality: 0.5)!.write(to: tmp)
        r = try await store.submit(relayID: r.id, media: CapturedMedia(type: .photo, fileURL: tmp, durationMs: nil))
        #expect(r.hasSubmitted(MockFixtures.meID))
        let next = RelayEngine.eligibleNext(r, excluding: MockFixtures.meID).first!.id
        r = try await store.passBaton(relayID: r.id, to: next)
        #expect(r.isHolder(next))
        try await store.simulateHolderTurn(relayID: r.id) { m, s in media.saveFixture(m, s) }
        try await store.simulateHolderTurn(relayID: r.id) { m, s in media.saveFixture(m, s) }
        let final = try await store.relay(r.id)
        #expect(final.status == .complete)
        let stats = try await store.group(g.id).stats
        #expect(stats == GroupStats(completedRelays: 1, currentStreak: 1))
        try await Task.sleep(for: .milliseconds(50))
        collector.cancel()
        #expect(events.contains(.ended(.complete)))
        #expect(events.contains(.batonReceived(to: next, from: MockFixtures.meID)))
    }

    @Test func expiryThroughStoreDefersAndMemberLeavingCancels() async throws {
        let (store, clock, _) = await makeStore()
        let relays = try await store.activeRelays()
        let r = relays[0]
        clock.advance(by: 2 * 3600 + 1)
        await store.processDeadlines()
        let after = try await store.relay(r.id)
        #expect(after.participant(MockFixtures.meID)?.state == .deferred)
        #expect(after.holder?.id != MockFixtures.meID)
        try await store.simulateMemberLeaves(groupID: MockFixtures.fridayID)
        let cancelled = try await store.relay(r.id)
        #expect(cancelled.status == .cancelled)
        #expect(try await store.group(MockFixtures.fridayID).stats.currentStreak == 0)
        #expect(try await store.activeRelays().isEmpty)
    }

    @Test func leavingGroupRemovesMeAndFailureInjectionSurfacesNetworkError() async throws {
        let (store, _, _) = await makeStore()
        try await store.leaveGroup(MockFixtures.courtID)
        #expect(try await store.groups().map(\.id) == [MockFixtures.fridayID])
        await store.setFailNextRequest(true)
        await #expect(throws: AppError.network) { _ = try await store.groups() }
        #expect(try await store.groups().count == 1, "only the next request fails")
    }

    @Test func blockedCreatorHidesTheirInvite() async throws {
        let (store, _, _) = await makeStore()
        try await store.block(MockFixtures.sam.id)
        await #expect(throws: AppError.self) { _ = try await store.invitePreview(code: "PASS-BR22") }
        try await store.unblock(MockFixtures.sam.id)
        _ = try await store.invitePreview(code: "PASS-BR22")
    }

    @Test func sessionStoreRoundTrips() {
        let defaults = UserDefaults(suiteName: "pass-tests-\(UUID().uuidString)")!
        let s = UserDefaultsSessionStore(defaults: defaults)
        #expect(s.loadSession() == nil)
        s.saveSession(Session(userID: "me", onboardingComplete: true))
        s.pendingInviteCode = "PASS-AB12"
        #expect(s.loadSession()?.onboardingComplete == true)
        #expect(s.pendingInviteCode == "PASS-AB12")
        s.wipeAll()
        #expect(s.loadSession() == nil && s.pendingInviteCode == nil)
    }
}

private extension LocalMediaStore {
    @MainActor func saveFixture(_ m: UserSummary, _ seed: Int) -> String {
        let name = "fixture-\(m.id.raw)-\(seed).jpg"
        _ = try? saveJPEG(UIImage(systemName: "circle.fill")!, quality: 0.5, fileName: name)
        return name
    }
}
