import Foundation
import Observation

/// Who is signed in and where they are in the entry flow. Owns the pending invite so an invited user is taken to the
/// invitation before Home (spec §3).
@MainActor
@Observable
final class AppSession {
    enum State: Equatable { case loading, signedOut, onboarding, signedIn }

    private(set) var state: State = .loading {
        didSet { if state != oldValue { stateDidChange?(state) } }
    }
    /// Composition-root hook (device-token registration, clock sync). Not observed by views.
    @ObservationIgnored var stateDidChange: (@MainActor (State) -> Void)?
    private(set) var user: User?
    private(set) var isWorking = false
    var lastError: AppError?

    /// Invite code received by deep link before sign-in/onboarding finished. Cleared when the invite flow is shown.
    var pendingInviteCode: String? {
        didSet { sessionStore.pendingInviteCode = pendingInviteCode }
    }

    private let auth: any AuthService
    private let users: any UserRepository
    private let sessionStore: any SessionStore
    private var activeTask: Task<Void, Never>?

    init(auth: any AuthService, users: any UserRepository, sessionStore: any SessionStore) {
        self.auth = auth
        self.users = users
        self.sessionStore = sessionStore
        self.pendingInviteCode = sessionStore.pendingInviteCode
    }

    func bootstrap() async {
        if let session = await auth.restoreSession() {
            user = sessionStore.loadUser()
            state = session.onboardingComplete ? .signedIn : .onboarding
        } else {
            state = .signedOut
        }
    }

    func signInDemo() {
        run { [auth] in try await auth.signInDemo() }
    }

    func signIn(with credential: AppleCredential) {
        run { [auth] in try await auth.signIn(with: credential) }
    }

    private func run(_ operation: @escaping @Sendable () async throws -> Session) {
        guard !isWorking else { return } // ignore repeated taps while a sign-in is in flight
        isWorking = true
        lastError = nil
        activeTask?.cancel()
        activeTask = Task { [weak self] in
            defer { self?.isWorking = false }
            do {
                let session = try await operation()
                guard let self, !Task.isCancelled else { return }
                self.user = self.sessionStore.loadUser()
                self.state = session.onboardingComplete ? .signedIn : .onboarding
            } catch {
                let e = AppError.wrap(error)
                if !e.isCancellation { self?.lastError = e }
            }
        }
    }

    /// Returns false (and sets `lastError`) when the profile could not be saved.
    func completeOnboarding(displayName: String, dateOfBirth: Date, avatarFileName: String?) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            user = try await users.completeOnboarding(displayName: displayName, dateOfBirth: dateOfBirth, avatarFileName: avatarFileName)
            return true
        } catch {
            let e = AppError.wrap(error)
            if !e.isCancellation { lastError = e }
            return false
        }
    }

    /// Called after the final onboarding step (notification prompt). The profile was already saved.
    func finishOnboarding() { state = .signedIn }

    func refreshUser() async {
        if let u = try? await users.currentUser() { user = u }
    }

    func signOut() async {
        await auth.signOut()
        user = nil
        pendingInviteCode = nil
        state = .signedOut
    }

    func deleteAccount() async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            try await auth.deleteAccount()
            user = nil
            pendingInviteCode = nil
            state = .signedOut
            return true
        } catch {
            lastError = AppError.wrap(error)
            return false
        }
    }
}
