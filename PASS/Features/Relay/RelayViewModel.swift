import Foundation
import Observation

/// Shared state for the Baton, Pass Baton, Progress and Complete screens of one relay.
@MainActor
@Observable
final class RelayViewModel {
    let relayID: RelayID
    private(set) var relay: Loadable<Relay> = .idle
    private(set) var isWorking = false
    var actionError: String?
    var selectedNext: UserID?
    private let deps: AppDependencies
    private var generation = 0

    init(relayID: RelayID, deps: AppDependencies) {
        self.relayID = relayID
        self.deps = deps
    }

    var me: UserID? { deps.session.user?.id }
    var rules: RelayRules { deps.configuration.rules }
    var current: Relay? { relay.value }
    var isMyTurn: Bool { if let me, let r = current { return r.isHolder(me) } else { return false } }
    var haveSubmitted: Bool { if let me, let r = current { return r.hasSubmitted(me) } else { return false } }
    var isRescue: Bool { current?.currentTurn?.isRescue ?? false }
    var eligibleNext: [RelayParticipant] { guard let me, let r = current else { return [] }; return RelayEngine.eligibleNext(r, excluding: me) }

    /// Fraction of the current window already elapsed (for the thin bar under the countdown).
    func windowFraction(now: Date) -> Double {
        guard let t = current?.currentTurn else { return 0 }
        let total = t.deadline.timeIntervalSince(t.startedAt)
        guard total > 0 else { return 1 }
        return min(1, max(0, now.timeIntervalSince(t.startedAt) / total))
    }

    func load(showLoading: Bool = true) async {
        generation += 1
        let gen = generation
        if showLoading, relay.value == nil { relay = .loading }
        do {
            let r = try await deps.relays.relay(relayID)
            guard gen == generation else { return }
            relay = .loaded(r)
        } catch {
            let e = AppError.wrap(error)
            guard gen == generation, !e.isCancellation else { return }
            if relay.value == nil { relay = .failed(e) }
        }
    }

    func observeChanges() async {
        for await change in deps.changes.changes() {
            guard !Task.isCancelled else { return }
            if change == .relays || change == .all { await load(showLoading: false) }
        }
    }

    func openCamera() { deps.router.fullScreen = .capture(relayID) }

    func pass() async {
        guard !isWorking, let to = selectedNext else { return }
        isWorking = true
        actionError = nil
        defer { isWorking = false }
        do {
            let r = try await deps.relays.passBaton(relayID: relayID, to: to)
            relay = .loaded(r)
            Haptics.success()
            deps.router.replaceStack(with: [.progress(relayID)])
        } catch {
            let e = AppError.wrap(error)
            if !e.isCancellation { actionError = e.userMessage; await load(showLoading: false) }
        }
    }

    func watchReveal() { deps.router.fullScreen = .reveal(relayID) }
    func goHome() { deps.router.popToRoot() }
    func startAnother() { guard let r = current else { return }; deps.router.replaceStack(with: [.newRelayChallenge(r.groupID)]) }

    // MARK: Demo controls (mock backend only)

    var demoAvailable: Bool { deps.configuration.demoControlsEnabled && deps.mockStore != nil }

    func demoNextMemberGoes() async {
        guard let store = deps.mockStore else { return }
        let media = deps.media
        do {
            try await store.simulateHolderTurn(relayID: relayID) { member, seed in FixtureMediaFactory.ensurePhoto(for: member, seed: seed, in: media) }
        } catch { actionError = AppError.wrap(error).userMessage }
    }

    func demoHolderDrops() async {
        guard let store = deps.mockStore else { return }
        try? await store.simulateExpiry(relayID: relayID)
    }

    func demoAdvance(_ seconds: TimeInterval) async {
        deps.clock.advance(by: seconds)
        await deps.mockStore?.processDeadlines()
        await load(showLoading: false)
    }
}
