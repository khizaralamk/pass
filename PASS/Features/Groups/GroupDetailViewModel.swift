import Foundation
import Observation

/// One group: members, stats, active relay, invite, history link, safety actions (spec §5, §7, §24, §26).
@MainActor
@Observable
final class GroupDetailViewModel {
    struct Content: Equatable {
        var group: Group
        var activeRelay: Relay?
    }

    let groupID: GroupID
    private(set) var content: Loadable<Content> = .idle
    private(set) var isWorking = false
    var actionError: AppError?
    private let deps: AppDependencies
    private var generation = 0

    init(groupID: GroupID, deps: AppDependencies) {
        self.groupID = groupID
        self.deps = deps
    }

    var me: UserID? { deps.session.user?.id }
    var rules: RelayRules { deps.configuration.rules }
    var configuration: AppConfiguration { deps.configuration }

    var group: Group? { content.value?.group }
    var isCreator: Bool { if let me, let g = group { return g.isCreator(me) } else { return false } }
    var canStartRelay: Bool { (group?.memberCount ?? 0) >= rules.minMembersToStart && content.value?.activeRelay == nil }
    var friendsNeeded: Int { max(0, rules.minMembersToStart - (group?.memberCount ?? 0)) }
    var inviteLink: URL? { group.map { deps.configuration.inviteLink(for: $0.inviteCode) } }

    func load(showLoading: Bool = true) async {
        generation += 1
        let gen = generation
        if showLoading, content.value == nil { content = .loading }
        do {
            async let group = deps.groups.group(groupID)
            async let relays = deps.relays.activeRelays()
            let (g, rs) = try await (group, relays)
            guard gen == generation else { return }
            content = .loaded(Content(group: g, activeRelay: rs.first { $0.groupID == groupID }))
        } catch {
            let e = AppError.wrap(error)
            guard gen == generation, !e.isCancellation else { return }
            if content.value == nil { content = .failed(e) }
        }
    }

    func observeChanges() async {
        for await _ in deps.changes.changes() {
            guard !Task.isCancelled else { return }
            await load(showLoading: false)
        }
    }

    /// Spec §6: a second relay attempt goes to the existing one.
    func startRelayTapped() {
        if let relay = content.value?.activeRelay {
            deps.router.push(.progress(relay.id))
        } else if canStartRelay {
            deps.router.push(.newRelayChallenge(groupID))
        }
    }

    func viewProgress() {
        guard let relay = content.value?.activeRelay else { return }
        deps.router.show(relay: relay)
    }

    @discardableResult
    private func perform(_ work: @escaping () async throws -> Void) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        actionError = nil
        defer { isWorking = false }
        do { try await work(); return true } catch {
            let e = AppError.wrap(error)
            if !e.isCancellation { actionError = e }
            return false
        }
    }

    func leaveGroup() async -> Bool {
        let ok = await perform { [deps, groupID] in try await deps.groups.leaveGroup(groupID) }
        if ok { deps.router.popToRoot(); deps.router.showToast("You left the group") }
        return ok
    }

    func removeMember(_ id: UserID) async -> Bool {
        let ok = await perform { [deps, groupID] in try await deps.groups.removeMember(id, from: groupID) }
        if ok { deps.router.showToast("Member removed") }
        return ok
    }

    func block(_ user: UserSummary) async -> Bool {
        let ok = await perform { [deps] in try await deps.users.block(user.id) }
        if ok { deps.router.showToast("\(user.firstName) blocked") }
        return ok
    }

    func report(_ target: ReportTarget, reason: ReportReason, details: String) async -> Bool {
        let ok = await perform { [deps] in try await deps.users.report(target: target, reason: reason, details: details) }
        if ok { deps.router.showToast("Report sent. Thank you.") }
        return ok
    }

    // Demo controls (mock only)
    var demoAvailable: Bool { deps.configuration.demoControlsEnabled && deps.mockStore != nil }
    func demoSimulateJoin() async {
        guard let store = deps.mockStore else { return }
        do { let u = try await store.simulateJoin(groupID: groupID); deps.router.showToast("\(u.displayName) joined", emoji: "👋") }
        catch { actionError = AppError.wrap(error) }
    }
    func demoMemberLeaves() async {
        guard let store = deps.mockStore else { return }
        try? await store.simulateMemberLeaves(groupID: groupID)
    }
}
