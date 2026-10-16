import Foundation
import Supabase

/// Supabase Auth. Sign in with Apple goes straight to GoTrue (`signInWithIdToken`), so there is no custom endpoint; the
/// Keychain-backed session is restored by the SDK on launch. `SessionStore` keeps only the cached profile and the
/// `onboardingComplete` marker so a returning user can reach Home offline.
final class SupabaseAuthService: AuthService, @unchecked Sendable {
    private let backend: SupabaseBackend
    private let users: SupabaseUserRepository
    private let sessionStore: any SessionStore
    private let clock: any DateProvider

    init(backend: SupabaseBackend, users: SupabaseUserRepository, sessionStore: any SessionStore, clock: any DateProvider) {
        self.backend = backend
        self.users = users
        self.sessionStore = sessionStore
        self.clock = clock
    }

    func restoreSession() async -> PASS.Session? {
        let auth = backend.client.auth
        guard auth.currentSession != nil else {
            sessionStore.clearSession()
            return nil
        }
        do {
            // Refreshes an expired token; throws when the refresh is rejected (revoked) or the network is down.
            _ = try await auth.session
        } catch {
            if SupabaseErrorMapping.map(error) == .network { return sessionStore.loadSession() }
            sessionStore.clearSession()
            return nil
        }
        do {
            return try await establish(suggestedName: nil)
        } catch {
            // Offline or server hiccup after a valid refresh: trust the cached marker so Home still opens.
            return sessionStore.loadSession()
        }
    }

    func signIn(with credential: AppleCredential) async throws -> PASS.Session {
        guard let tokenData = credential.identityToken, let idToken = String(data: tokenData, encoding: .utf8), !idToken.isEmpty else {
            throw AppError.unknown("Sign in with Apple didn't return a token. Please try again.")
        }
        do {
            _ = try await backend.client.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: credential.nonce))
        } catch {
            throw SupabaseErrorMapping.map(error)
        }
        return try await establish(suggestedName: credential.fullName)
    }

    /// Email/password identity per simulator so several simulators can play one group. DEBUG only; the backend's
    /// local/staging projects have email confirmation disabled for `@pass.test`.
    func signInDemo() async throws -> PASS.Session {
        #if DEBUG
        let device = Self.demoDeviceID()
        let email = "demo+\(device)@pass.test"
        let password = "pass-demo-\(device)"
        let auth = backend.client.auth
        do {
            _ = try await auth.signIn(email: email, password: password)
        } catch {
            do {
                let response = try await auth.signUp(email: email, password: password)
                guard response.session != nil else {
                    throw AppError.permissionDenied("Demo sign-in needs email confirmation disabled on this backend.")
                }
            } catch {
                throw SupabaseErrorMapping.map(error)
            }
        }
        return try await establish(suggestedName: nil)
        #else
        throw AppError.permissionDenied("The demo isn't available in this build.")
        #endif
    }

    func signOut() async {
        do {
            try await backend.client.auth.signOut()
        } catch {
            // Revocation failed (offline?); drop the local session anyway so the UI returns to the splash.
            try? await backend.client.auth.signOut(scope: .local)
        }
        sessionStore.clearSession()
    }

    /// Edge Function `delete-account` revokes the Apple token, deletes storage objects and the auth user (cascades).
    func deleteAccount() async throws {
        try await backend.invokeVoid("delete-account", body: EmptyBody())
        try? await backend.client.auth.signOut(scope: .local)
        sessionStore.clearSession()
    }

    // MARK: - Private

    /// Loads the profile (`get_me`), caches it for `AppSession`, and derives the onboarding state (`nil` → onboarding).
    private func establish(suggestedName: String?) async throws -> PASS.Session {
        let userID = try backend.currentUserID()
        let profile = try await users.fetchProfile()
        let user = profile ?? Self.placeholder(id: userID, suggestedName: suggestedName, now: clock.now())
        sessionStore.saveUser(user)
        let session = PASS.Session(userID: userID, onboardingComplete: profile != nil)
        sessionStore.saveSession(session)
        return session
    }

    /// Stands in until `complete_onboarding`; its colour is the one sent to the server at onboarding.
    static func placeholder(id: UserID, suggestedName: String?, now: Date) -> PASS.User {
        let name = suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return PASS.User(id: id, displayName: (name?.isEmpty == false) ? (name ?? "You") : "You",
                         colorHex: SupabaseUserRepository.defaultColorHex(for: id), avatarFileName: nil,
                         memberSince: now, dateOfBirth: nil)
    }

    #if DEBUG
    private static func demoDeviceID() -> String {
        let key = "pass.demo.deviceID"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let fresh = String(UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(12))
        UserDefaults.standard.set(fresh, forKey: key)
        return fresh
    }
    #endif
}
