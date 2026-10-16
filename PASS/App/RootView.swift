import SwiftUI

/// Switches between the entry flow and the signed-in shell based on `AppSession.state`.
struct RootView: View {
    @State private var deps = AppDependencies.live()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        content
            .dependencies(deps)
            .task { await deps.bootstrap() }
            .onOpenURL { url in
                let signedIn = deps.session.state == .signedIn
                if deps.router.handle(url: url, isSignedIn: signedIn), !signedIn {
                    deps.session.pendingInviteCode = deps.router.deferredInviteCode
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { deps.handleForeground() }
            }
            .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var content: some View {
        switch deps.session.state {
        case .loading:
            SplashView(mode: .loading)
        case .signedOut:
            SplashView(mode: .signIn)
        case .onboarding:
            OnboardingView()
        case .signedIn:
            MainNavigationView()
        }
    }
}
