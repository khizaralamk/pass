import SwiftUI
import AuthenticationServices

/// Figma S1. In `.loading` only the wordmark shows (returning user → Home). In `.signIn` the Apple button appears.
struct SplashView: View {
    enum Mode { case loading, signIn }
    let mode: Mode
    @Environment(AppSession.self) private var session
    @State private var ready = false
    @State private var currentNonce: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        PassScreen(background: .black) {
            VStack {
                Spacer()
                VStack(spacing: 28) {
                    BrandTile()
                    VStack(spacing: 8) {
                        Text("PASS").outfit(68, .black, tracking: -4).foregroundStyle(.white)
                            .accessibilityAddTraits(.isHeader)
                        Text("Private challenges. Group reveals.").inter(14).foregroundStyle(PassColor.textTertiary)
                    }
                }
                .opacity(ready || reduceMotion ? 1 : 0)
                .offset(y: ready || reduceMotion ? 0 : 12)
                Spacer()
                if mode == .signIn {
                    BottomActions {
                        if let error = session.lastError {
                            InlineMessage(text: error.userMessage).multilineTextAlignment(.center)
                        }
                        appleButton
                        #if DEBUG
                        PassButton(title: "Try the demo →", variant: .surface, isLoading: session.isWorking) {
                            session.signInDemo()
                        }
                        .accessibilityIdentifier("splash.demo")
                        #endif
                        Text("By continuing you agree to our Terms & Privacy Policy")
                            .inter(11).foregroundStyle(PassColor.textFaint).multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }
                    .padding(.bottom, 20)
                    .fadeUp(1)
                } else {
                    Color.clear.frame(height: 180)
                }
            }
        }
        .onAppear { withAnimation(.easeOut(duration: 0.5).delay(0.2)) { ready = true } }
    }

    /// The official button (required by Apple's guidelines). The mock auth accepts whatever credential comes back.
    private var appleButton: some View {
        SignInWithAppleButton(.continue) { request in
            request.requestedScopes = [.fullName]
            // The backend verifies the token's nonce claim against the raw value we keep (replay protection).
            let nonce = AppleNonce.random()
            currentNonce = nonce
            request.nonce = AppleNonce.sha256(nonce)
        } onCompletion: { result in
            switch result {
            case .success(let authorization):
                guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
                let name = [credential.fullName?.givenName, credential.fullName?.familyName].compactMap { $0 }.joined(separator: " ")
                session.signIn(with: AppleCredential(userIdentifier: credential.user, identityToken: credential.identityToken,
                                                     fullName: name.isEmpty ? nil : name, nonce: currentNonce))
            case .failure(let error):
                // ASAuthorizationError.canceled (1001) is the user backing out; not an error to show.
                if (error as NSError).code != ASAuthorizationError.canceled.rawValue {
                    session.lastError = .unknown("Sign in with Apple didn't complete. Please try again.")
                }
            }
        }
        .signInWithAppleButtonStyle(.white)
        .frame(height: 56)
        .clipShape(Capsule())
        .disabled(session.isWorking)
        .opacity(session.isWorking ? 0.6 : 1)
        .accessibilityIdentifier("splash.apple")
    }
}
