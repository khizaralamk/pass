import SwiftUI

/// The signed-in shell: one `NavigationStack` rooted at Home, plus full-screen covers for camera, reveal and invites.
struct MainNavigationView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppSession.self) private var session
    @Environment(\.dependencies) private var deps

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.path) {
            HomeView()
                .navigationDestination(for: Route.self) { route in
                    RouteView(route: route)
                }
        }
        .tint(PassColor.violet)
        .fullScreenCover(item: $router.fullScreen) { route in
            if let deps {
                FullScreenRouteView(route: route).dependencies(deps)
            }
        }
        .toast($router.toast)
        .onAppear(perform: restorePendingInvite)
        .onChange(of: session.pendingInviteCode) { _, _ in restorePendingInvite() }
    }

    /// Spec §3: an invited user sees the invitation before Home.
    private func restorePendingInvite() {
        if let code = session.pendingInviteCode ?? router.deferredInviteCode {
            session.pendingInviteCode = nil
            router.deferredInviteCode = nil
            router.fullScreen = .invite(code: code)
        }
    }
}

/// Maps a `Route` to its screen. Each screen builds its own view model from the dependencies.
struct RouteView: View {
    let route: Route
    @Environment(\.dependencies) private var deps

    var body: some View {
        if let deps {
            switch route {
            case .profile: ProfileView(deps: deps)
            case .groupDetail(let id): GroupDetailView(model: GroupDetailViewModel(groupID: id, deps: deps))
            case .groupMembers(let id): GroupMembersView(model: GroupDetailViewModel(groupID: id, deps: deps))
            case .groupHistory(let id): RelayHistoryView(model: RelayHistoryViewModel(groupID: id, deps: deps))
            case .createGroupName: CreateGroupNameView(deps: deps)
            case .createGroupInvite(let id): CreateGroupInviteView(model: GroupDetailViewModel(groupID: id, deps: deps), mode: .creating)
            case .groupCreated(let id): GroupCreatedView(model: GroupDetailViewModel(groupID: id, deps: deps))
            case .newRelayGroup(let preselected): NewRelayGroupView(model: NewRelayViewModel(deps: deps, preselected: preselected))
            case .newRelayChallenge(let gid): NewRelayChallengeView(model: NewRelayViewModel(deps: deps, preselected: gid))
            case .newRelayReview(let gid, let challenge): NewRelayReviewView(model: NewRelayViewModel(deps: deps, preselected: gid, challenge: challenge))
            case .baton(let id): BatonView(model: RelayViewModel(relayID: id, deps: deps))
            case .passBaton(let id): PassBatonView(model: RelayViewModel(relayID: id, deps: deps))
            case .progress(let id): RelayProgressView(model: RelayViewModel(relayID: id, deps: deps))
            case .relayComplete(let id): RelayCompleteView(model: RelayViewModel(relayID: id, deps: deps))
            case .postReveal(let id): PostRevealView(model: RevealViewModel(relayID: id, deps: deps))
            case .notificationSettings: NotificationSettingsView(deps: deps)
            case .privacySettings: PrivacySettingsView(deps: deps)
            case .about: AboutView()
            case .support: SupportView(deps: deps)
            case .inviteCodeEntry: InviteCodeEntryView(deps: deps)
            }
        }
    }
}

struct FullScreenRouteView: View {
    let route: FullScreenRoute
    @Environment(\.dependencies) private var deps

    var body: some View {
        if let deps {
            switch route {
            case .capture(let id): CaptureFlowView(model: CaptureViewModel(relayID: id, deps: deps))
            case .reveal(let id): RevealPlayerView(model: RevealViewModel(relayID: id, deps: deps))
            case .invite(let code): InviteFlowView(model: InviteViewModel(code: code, deps: deps))
            }
        }
    }
}
