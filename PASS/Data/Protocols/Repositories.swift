import Foundation
import UIKit

// MARK: - Data-access contracts
// Views and view models depend only on these protocols. `Data/Mock` implements them in memory today; the backend phase adds
// `Supabase*` or `Firebase*` implementations with the same signatures (see Documentation/BACKEND-INTEGRATION.md).

/// A credential from Sign in with Apple. Only the opaque parts a backend needs; never the raw name/email beyond first use.
/// `nonce` is the raw value whose SHA-256 was put on the request; Supabase verifies it against the token's `nonce` claim.
struct AppleCredential: Sendable, Hashable {
    var userIdentifier: String
    var identityToken: Data?
    var fullName: String?
    var nonce: String?
}

protocol AuthService: Sendable {
    func restoreSession() async -> Session?
    /// Signs in with a real Apple credential. The mock accepts any credential.
    func signIn(with credential: AppleCredential) async throws -> Session
    /// DEBUG/simulator path: creates a demo identity without Apple. Compiled out of Release builds by the caller.
    func signInDemo() async throws -> Session
    func signOut() async
    func deleteAccount() async throws
}

protocol UserRepository: Sendable {
    func currentUser() async throws -> User
    func completeOnboarding(displayName: String, dateOfBirth: Date, avatarFileName: String?) async throws -> User
    func notificationPreferences() async throws -> NotificationPreferences
    func updateNotificationPreferences(_ prefs: NotificationPreferences) async throws
    func blockedUsers() async throws -> [UserSummary]
    func block(_ userID: UserID) async throws
    func unblock(_ userID: UserID) async throws
    func report(target: ReportTarget, reason: ReportReason, details: String) async throws
    /// APNs token (hex) for the signed-in user. The mock ignores it; the backend upserts `device_tokens`.
    func registerDeviceToken(_ token: String, environment: APNSEnvironment) async throws
}

/// Which APNs gateway the token belongs to. Mirrors the `aps-environment` entitlement: debug builds use the sandbox.
enum APNSEnvironment: String, Sendable {
    case development, production

    static var current: APNSEnvironment {
        #if DEBUG
        return .development
        #else
        return .production
        #endif
    }
}

protocol GroupRepository: Sendable {
    func groups() async throws -> [Group]
    func group(_ id: GroupID) async throws -> Group
    func createGroup(name: String, emoji: String) async throws -> Group
    func invitePreview(code: String) async throws -> InvitePreview
    func joinGroup(code: String) async throws -> Group
    func leaveGroup(_ id: GroupID) async throws
    func removeMember(_ userID: UserID, from groupID: GroupID) async throws
}

/// Media captured in-app and waiting to be submitted.
struct CapturedMedia: Sendable, Hashable {
    var type: MediaType
    var fileURL: URL
    var durationMs: Int?
}

protocol RelayRepository: Sendable {
    func activeRelays() async throws -> [Relay]
    func relay(_ id: RelayID) async throws -> Relay
    func history(groupID: GroupID) async throws -> [Relay]
    func challenges() async throws -> [Challenge]
    func startRelay(groupID: GroupID, challengeTitle: String) async throws -> Relay
    func submit(relayID: RelayID, media: CapturedMedia) async throws -> Relay
    func passBaton(relayID: RelayID, to userID: UserID) async throws -> Relay
}

/// Builds the Reveal input for a finished relay. The mock derives it from the relay (`RevealManifest.make`); the backend
/// asks the server for signed media URLs and caches the files in the `MediaStore` so playback and export stay local.
protocol RevealManifestProvider: Sendable {
    /// `nil` when the relay has no Reveal (active, cancelled, or fewer than 3 submissions).
    func manifest(for relay: Relay) async throws -> RevealManifest?
}

/// Change notifications so screens refresh after mutations and after simulated server events.
enum DataChange: Sendable, Equatable {
    case groups
    case relays
    case user
    case all
}

protocol DataChangeSource: Sendable {
    func changes() -> AsyncStream<DataChange>
}

/// Local files for captured and fixture media. The backend phase keeps this for the upload queue and the Reveal cache.
protocol MediaStore: Sendable {
    func url(for fileName: String) -> URL
    func importFile(at url: URL, preferredExtension: String) throws -> String
    func saveJPEG(_ image: UIImage, quality: CGFloat, fileName: String?) throws -> String
    func delete(fileName: String)
    func exists(fileName: String) -> Bool
}

/// Persists only the mock session marker and a pending invite code. Real tokens belong in the Keychain (backend phase).
protocol SessionStore: Sendable {
    func loadSession() -> Session?
    func saveSession(_ session: Session)
    func clearSession()
    func loadUser() -> User?
    func saveUser(_ user: User)
    var pendingInviteCode: String? { get nonmutating set }
    var notificationPromptShown: Bool { get nonmutating set }
}

/// Wraps UNUserNotificationCenter. Remote push (APNs) arrives in the backend phase; the mock schedules local notifications
/// for simulated events so the tap → relay routing (spec §15) can be exercised today.
protocol NotificationService: Sendable {
    func authorizationStatus() async -> NotificationAuthorization
    func requestAuthorization() async -> Bool
    func scheduleLocal(title: String, body: String, relayID: RelayID?) async
}

enum NotificationAuthorization: Sendable { case notDetermined, authorized, denied }
