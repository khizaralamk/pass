import Foundation
import Observation

/// New Relay → Choose Group → Choose/Create Challenge → Review → Start (spec §8). The creator goes first (§9).
@MainActor
@Observable
final class NewRelayViewModel {
    struct GroupOption: Identifiable, Equatable {
        var group: Group
        var activeRelay: Relay?
        var id: GroupID { group.id }
    }

    private(set) var groups: Loadable<[GroupOption]> = .idle
    private(set) var challenges: Loadable<[Challenge]> = .idle
    var selectedGroupID: GroupID?
    var selectedChallenge: String?
    var customChallenge = ""
    var isWritingOwn = false
    var challengeError: String?
    private(set) var isStarting = false
    var startError: String?
    private let deps: AppDependencies

    init(deps: AppDependencies, preselected: GroupID?, challenge: String? = nil) {
        self.deps = deps
        self.selectedGroupID = preselected
        self.selectedChallenge = challenge
    }

    var rules: RelayRules { deps.configuration.rules }
    var selectedGroup: Group? { groups.value?.first { $0.id == selectedGroupID }?.group }

    /// The challenge that would be used: the custom text when writing your own, else the selected preset.
    var activeChallenge: String? {
        if isWritingOwn { let t = Validators.normalized(customChallenge); return t.isEmpty ? nil : t }
        return selectedChallenge
    }

    func loadGroups() async {
        if groups.value == nil { groups = .loading }
        do {
            async let g = deps.groups.groups()
            async let r = deps.relays.activeRelays()
            let (gs, rs) = try await (g, r)
            groups = .loaded(gs.map { g in GroupOption(group: g, activeRelay: rs.first { r in r.groupID == g.id }) })
        } catch {
            let e = AppError.wrap(error); if !e.isCancellation, groups.value == nil { groups = .failed(e) }
        }
    }

    func loadChallenges() async {
        if challenges.value == nil { challenges = .loading }
        do { challenges = .loaded(try await deps.relays.challenges()) }
        catch { let e = AppError.wrap(error); if !e.isCancellation, challenges.value == nil { challenges = .failed(e) } }
    }

    func loadGroupIfNeeded() async {
        guard selectedGroup == nil else { return }
        await loadGroups()
    }

    func isSelectable(_ option: GroupOption) -> Bool {
        option.activeRelay == nil && option.group.memberCount >= rules.minMembersToStart
    }

    func tap(_ option: GroupOption) {
        if let relay = option.activeRelay {
            deps.router.push(.progress(relay.id)) // spec §6: direct them to the existing relay
        } else if isSelectable(option) {
            selectedGroupID = option.id
        }
    }

    func continueToChallenge() {
        guard let id = selectedGroupID else { return }
        deps.router.push(.newRelayChallenge(id))
    }

    func selectPreset(_ title: String) {
        selectedChallenge = title
        isWritingOwn = false
        challengeError = nil
    }

    func continueToReview() {
        guard let gid = selectedGroupID else { return }
        if isWritingOwn {
            switch Validators.challengeTitle(customChallenge) {
            case .failure(let e): challengeError = e.message; return
            case .success(let t): challengeError = nil; deps.router.push(.newRelayReview(gid, challenge: t))
            }
        } else if let c = selectedChallenge {
            deps.router.push(.newRelayReview(gid, challenge: c))
        }
    }

    /// Starts the relay, then opens the camera over the Baton screen. Cancelling the camera leaves the user on Baton.
    func start() async {
        guard !isStarting, let gid = selectedGroupID, let challenge = selectedChallenge else { return }
        isStarting = true
        startError = nil
        defer { isStarting = false }
        do {
            let relay = try await deps.relays.startRelay(groupID: gid, challengeTitle: challenge)
            Haptics.success()
            deps.router.replaceStack(with: [.baton(relay.id)])
            deps.router.fullScreen = .capture(relay.id)
        } catch {
            let e = AppError.wrap(error)
            if !e.isCancellation { startError = e.userMessage }
        }
    }
}
