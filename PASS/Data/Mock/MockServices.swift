import Foundation
import UIKit
import UserNotifications

// MARK: - Auth

/// Frontend-phase authentication. Accepts a real Apple credential (the button works on a device) or a demo identity.
/// The real implementation exchanges the identity token with the backend; see Documentation/BACKEND-INTEGRATION.md.
struct MockAuthService: AuthService {
    let store: MockDataStore
    let sessionStore: any SessionStore
    let clock: any DateProvider

    func restoreSession() async -> Session? {
        guard let session = sessionStore.loadSession(), let user = sessionStore.loadUser() else { return nil }
        await store.setCurrentUser(user)
        return session
    }

    func signIn(with credential: AppleCredential) async throws -> Session {
        try await Task.sleep(for: .milliseconds(400))
        return await establish(suggestedName: credential.fullName)
    }

    func signInDemo() async throws -> Session {
        try await Task.sleep(for: .milliseconds(400))
        return await establish(suggestedName: nil)
    }

    private func establish(suggestedName: String?) async -> Session {
        // A returning user (same device) keeps their profile; a first-time user gets a placeholder until onboarding.
        let user = sessionStore.loadUser() ?? {
            var u = MockFixtures.placeholderMe(now: clock.now())
            if let n = suggestedName, !n.isEmpty { u.displayName = n }
            return u
        }()
        let session = Session(userID: user.id, onboardingComplete: sessionStore.loadSession()?.onboardingComplete ?? false)
        sessionStore.saveUser(user)
        sessionStore.saveSession(session)
        await store.setCurrentUser(user)
        return session
    }

    func signOut() async {
        sessionStore.clearSession()
        await store.setCurrentUser(nil)
    }

    func deleteAccount() async throws {
        try await Task.sleep(for: .milliseconds(600))
        sessionStore.clearSession()
        await store.resetAll(keepUser: false)
    }
}

// MARK: - Repositories (thin adapters over the store)

struct MockUserRepository: UserRepository {
    let store: MockDataStore
    let sessionStore: any SessionStore

    func currentUser() async throws -> User { try await store.currentUser() }

    func completeOnboarding(displayName: String, dateOfBirth: Date, avatarFileName: String?) async throws -> User {
        // The DOB was validated by the caller (16+). It is deliberately not stored on the device; the backend keeps it.
        _ = dateOfBirth
        let user = try await store.updateCurrentUser { u in
            u.displayName = displayName
            if let avatarFileName { u.avatarFileName = avatarFileName }
        }
        sessionStore.saveUser(user)
        if var s = sessionStore.loadSession() { s.onboardingComplete = true; sessionStore.saveSession(s) }
        return user
    }

    func notificationPreferences() async throws -> NotificationPreferences { try await store.preferences() }
    func updateNotificationPreferences(_ prefs: NotificationPreferences) async throws { try await store.setPreferences(prefs) }
    func blockedUsers() async throws -> [UserSummary] { try await store.blockedUsers() }
    func block(_ userID: UserID) async throws { try await store.block(userID) }
    func unblock(_ userID: UserID) async throws { try await store.unblock(userID) }
    func report(target: ReportTarget, reason: ReportReason, details: String) async throws {
        try await store.report(target: target, reason: reason, details: details)
    }
    /// No pushes in the mock: `AppDependencies.dispatchNotifications` schedules local notifications instead.
    func registerDeviceToken(_ token: String, environment: APNSEnvironment) async throws {}
}

struct MockGroupRepository: GroupRepository {
    let store: MockDataStore
    func groups() async throws -> [Group] { try await store.groups() }
    func group(_ id: GroupID) async throws -> Group { try await store.group(id) }
    func createGroup(name: String, emoji: String) async throws -> Group { try await store.createGroup(name: name, emoji: emoji) }
    func invitePreview(code: String) async throws -> InvitePreview { try await store.invitePreview(code: code) }
    func joinGroup(code: String) async throws -> Group { try await store.joinGroup(code: code) }
    func leaveGroup(_ id: GroupID) async throws { try await store.leaveGroup(id) }
    func removeMember(_ userID: UserID, from groupID: GroupID) async throws { try await store.removeMember(userID, from: groupID) }
}

struct MockRelayRepository: RelayRepository {
    let store: MockDataStore
    func activeRelays() async throws -> [Relay] { try await store.activeRelays() }
    func relay(_ id: RelayID) async throws -> Relay { try await store.relay(id) }
    func history(groupID: GroupID) async throws -> [Relay] { try await store.history(groupID: groupID) }
    func challenges() async throws -> [Challenge] { try await store.challenges() }
    func startRelay(groupID: GroupID, challengeTitle: String) async throws -> Relay {
        try await store.startRelay(groupID: groupID, challengeTitle: challengeTitle)
    }
    func submit(relayID: RelayID, media: CapturedMedia) async throws -> Relay { try await store.submit(relayID: relayID, media: media) }
    func passBaton(relayID: RelayID, to userID: UserID) async throws -> Relay { try await store.passBaton(relayID: relayID, to: userID) }
}

/// The mock has every file locally, so the manifest is a pure projection of the relay.
struct MockRevealManifestProvider: RevealManifestProvider {
    func manifest(for relay: Relay) async throws -> RevealManifest? { RevealManifest.make(from: relay) }
}

struct MockDataChangeSource: DataChangeSource {
    let store: MockDataStore
    func changes() -> AsyncStream<DataChange> {
        AsyncStream { continuation in
            let task = Task {
                for await event in await store.events() {
                    if case .data(let change) = event { continuation.yield(change) }
                    if case .relay = event { continuation.yield(.relays) }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - Media files

/// Files under Application Support/Media. Captured media is copied here on submit; fixture photos are generated here.
struct LocalMediaStore: MediaStore {
    let directory: URL

    static func `default`() -> LocalMediaStore {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("Media", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return LocalMediaStore(directory: dir)
    }

    func url(for fileName: String) -> URL { directory.appendingPathComponent(fileName) }
    func exists(fileName: String) -> Bool { FileManager.default.fileExists(atPath: url(for: fileName).path) }

    func importFile(at source: URL, preferredExtension: String) throws -> String {
        let name = "capture-\(UUID().uuidString.lowercased()).\(preferredExtension)"
        do {
            try FileManager.default.copyItem(at: source, to: url(for: name))
        } catch {
            throw AppError.media("Couldn't save your capture. Please try again.")
        }
        return name
    }

    func saveJPEG(_ image: UIImage, quality: CGFloat, fileName: String?) throws -> String {
        let name = fileName ?? "image-\(UUID().uuidString.lowercased()).jpg"
        guard let data = image.jpegData(compressionQuality: quality) else { throw AppError.media("Couldn't encode the image.") }
        do { try data.write(to: url(for: name), options: .atomic) } catch { throw AppError.media("Couldn't save the image.") }
        return name
    }

    func delete(fileName: String) { try? FileManager.default.removeItem(at: url(for: fileName)) }
}

// MARK: - Session persistence

/// Mock session marker + profile in UserDefaults. Nothing secret is stored (no tokens). Keychain comes with the backend.
struct UserDefaultsSessionStore: SessionStore {
    let defaults: UserDefaults
    private let sessionKey = "pass.mock.session"
    private let userKey = "pass.mock.user"
    private let inviteKey = "pass.pendingInviteCode"
    private let promptKey = "pass.notificationPromptShown"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func loadSession() -> Session? { decode(sessionKey) }
    func saveSession(_ session: Session) { encode(session, sessionKey) }
    func clearSession() { defaults.removeObject(forKey: sessionKey) }
    func loadUser() -> User? { decode(userKey) }
    func saveUser(_ user: User) { encode(user, userKey) }

    var pendingInviteCode: String? {
        get { defaults.string(forKey: inviteKey) }
        nonmutating set { defaults.set(newValue, forKey: inviteKey) }
    }

    var notificationPromptShown: Bool {
        get { defaults.bool(forKey: promptKey) }
        nonmutating set { defaults.set(newValue, forKey: promptKey) }
    }

    func wipeAll() {
        [sessionKey, userKey, inviteKey, promptKey].forEach { defaults.removeObject(forKey: $0) }
    }

    private func decode<T: Decodable>(_ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return try? d.decode(T.self, from: data)
    }

    private func encode<T: Encodable>(_ value: T, _ key: String) {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        if let data = try? e.encode(value) { defaults.set(data, forKey: key) }
    }
}

// MARK: - Notifications

struct LocalNotificationService: NotificationService {
    func authorizationStatus() async -> NotificationAuthorization {
        let s = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        switch s {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        default: return .authorized
        }
    }

    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func scheduleLocal(title: String, body: String, relayID: RelayID?) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let relayID { content.userInfo = ["relayId": relayID.raw] }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
        try? await UNUserNotificationCenter.current().add(request)
    }
}
