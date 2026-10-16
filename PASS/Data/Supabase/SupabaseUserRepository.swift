import Foundation
import Supabase

/// Profile, preferences, blocks, reports and the APNs token, all through the contract's RPCs. The avatar is a JPEG in
/// the private `avatars` bucket (`<userId>.jpg`); a copy is kept in `LocalMediaStore` under the same name so
/// `MediaImageView` renders it like any other file.
final class SupabaseUserRepository: UserRepository, @unchecked Sendable {
    private let backend: SupabaseBackend
    private let sessionStore: any SessionStore
    private let media: any MediaStore
    private let clock: any DateProvider

    init(backend: SupabaseBackend, sessionStore: any SessionStore, media: any MediaStore, clock: any DateProvider) {
        self.backend = backend
        self.sessionStore = sessionStore
        self.media = media
        self.clock = clock
    }

    // MARK: - Profile

    /// `get_me` → `Profile | null`. `nil` means the account exists but onboarding has not run.
    func fetchProfile() async throws -> PASS.User? {
        guard let user: PASS.User = try await backend.rpcOptional("get_me") else { return nil }
        await cacheAvatarIfNeeded(user)
        return user
    }

    func currentUser() async throws -> PASS.User {
        guard let user = try await fetchProfile() else { throw AppError.notFound("Your profile") }
        sessionStore.saveUser(user)
        return user
    }

    func completeOnboarding(displayName: String, dateOfBirth: Date, avatarFileName: String?) async throws -> PASS.User {
        let userID = try backend.currentUserID()
        // The DOB never leaves the device (spec §3); the server stores only the verified flag.
        let ageVerified: Bool
        switch Validators.dateOfBirth(dateOfBirth, now: clock.now()) {
        case .success: ageVerified = true
        case .failure: ageVerified = false
        }
        let colorHex = sessionStore.loadUser()?.colorHex ?? Self.defaultColorHex(for: userID)
        let avatarPath = try await uploadAvatarIfNeeded(localFileName: avatarFileName, userID: userID)
        let user: PASS.User = try await backend.rpc("complete_onboarding", [
            "p_display_name": .string(displayName),
            "p_color_hex": .string(colorHex),
            "p_avatar_path": .string(avatarPath),
            "p_age_verified": .bool(ageVerified),
        ])
        sessionStore.saveUser(user)
        if var session = sessionStore.loadSession() {
            session.onboardingComplete = true
            sessionStore.saveSession(session)
        } else {
            sessionStore.saveSession(PASS.Session(userID: userID, onboardingComplete: true))
        }
        return user
    }

    // MARK: - Preferences

    func notificationPreferences() async throws -> NotificationPreferences {
        try await backend.rpc("get_notification_preferences")
    }

    func updateNotificationPreferences(_ prefs: NotificationPreferences) async throws {
        try await backend.rpcVoid("set_notification_preferences", ["p_prefs": .json(prefs)])
    }

    // MARK: - Safety

    func blockedUsers() async throws -> [UserSummary] {
        try await backend.rpc("get_blocked_users")
    }

    func block(_ userID: UserID) async throws {
        try await backend.rpcVoid("block_user", ["p_user_id": .string(userID.raw)])
    }

    func unblock(_ userID: UserID) async throws {
        try await backend.rpcVoid("unblock_user", ["p_user_id": .string(userID.raw)])
    }

    func report(target: ReportTarget, reason: ReportReason, details: String) async throws {
        var targetUser: String?
        var targetRelay: String?
        switch target {
        case .user(let id): targetUser = id.raw
        case .relay(let id): targetRelay = id.raw
        }
        try await backend.rpcVoid("report", [
            "p_target_user_id": .string(targetUser),
            "p_target_relay_id": .string(targetRelay),
            "p_reason": .string(reason.serverKey),
            "p_details": .string(details),
        ])
    }

    // MARK: - Push

    func registerDeviceToken(_ token: String, environment: APNSEnvironment) async throws {
        try await backend.rpcVoid("register_device_token", [
            "p_token": .string(token),
            "p_apns_env": .string(environment.rawValue),
        ])
    }

    // MARK: - Avatar

    static let avatarBucket = "avatars"

    /// Deterministic pick from the member palette so the same account keeps its colour across reinstalls.
    static func defaultColorHex(for id: UserID) -> String {
        let palette = PassColor.memberPaletteHex
        let sum = id.raw.utf8.reduce(0) { ($0 + Int($1)) % 100_000 }
        return palette[sum % max(palette.count, 1)]
    }

    private func uploadAvatarIfNeeded(localFileName: String?, userID: UserID) async throws -> String? {
        guard let localFileName, media.exists(fileName: localFileName) else { return nil }
        let remotePath = "\(userID.raw).jpg"
        let localURL = media.url(for: localFileName)
        guard let data = try? Data(contentsOf: localURL) else { throw AppError.media("Couldn't read your photo. Please try again.") }
        do {
            try await backend.client.storage.from(Self.avatarBucket)
                .upload(remotePath, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))
        } catch {
            throw SupabaseErrorMapping.map(error)
        }
        // Mirror it locally under the server name so the profile renders without a download.
        if localFileName != remotePath {
            let destination = media.url(for: remotePath)
            try? FileManager.default.removeItem(at: destination)
            try? FileManager.default.copyItem(at: localURL, to: destination)
        }
        return remotePath
    }

    private func cacheAvatarIfNeeded(_ user: PASS.User) async {
        guard let path = user.avatarFileName, !media.exists(fileName: path) else { return }
        guard let data = try? await backend.client.storage.from(Self.avatarBucket).download(path: path) else { return }
        try? data.write(to: media.url(for: path), options: .atomic)
    }
}
