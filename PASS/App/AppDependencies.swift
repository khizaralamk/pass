import Foundation
import SwiftUI
import UIKit

/// Composition root. Builds the object graph once at launch and hands protocol-typed services to the features.
/// `AppConfiguration.backend` picks the data layer: the in-app mock (default) or Supabase (`Data/Supabase`).
@MainActor
final class AppDependencies {
    let configuration: AppConfiguration
    let clock: AdjustableDateProvider
    let media: any MediaStore
    let sessionStore: any SessionStore
    let auth: any AuthService
    let users: any UserRepository
    let groups: any GroupRepository
    let relays: any RelayRepository
    let revealManifests: any RevealManifestProvider
    let changes: any DataChangeSource
    let notifications: any NotificationService
    let session: AppSession
    let router: AppRouter
    /// Mock-only handle for demo controls. `nil` once a real backend is wired in.
    let mockStore: MockDataStore?
    /// Keeps `clock` aligned with the server. `nil` for the mock, whose clock is the demo controls' to move.
    let serverClock: ServerClock?

    private var deadlineTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?
    private var deviceToken: String?
    private var registeredDeviceToken: String?

    init(configuration: AppConfiguration, clock: AdjustableDateProvider, media: any MediaStore, sessionStore: any SessionStore,
         auth: any AuthService, users: any UserRepository, groups: any GroupRepository, relays: any RelayRepository,
         revealManifests: any RevealManifestProvider, changes: any DataChangeSource, notifications: any NotificationService,
         mockStore: MockDataStore?, serverClock: ServerClock? = nil) {
        self.configuration = configuration
        self.clock = clock
        self.media = media
        self.sessionStore = sessionStore
        self.auth = auth
        self.users = users
        self.groups = groups
        self.relays = relays
        self.revealManifests = revealManifests
        self.changes = changes
        self.notifications = notifications
        self.mockStore = mockStore
        self.serverClock = serverClock
        self.session = AppSession(auth: auth, users: users, sessionStore: sessionStore)
        self.router = AppRouter(configuration: configuration)
        router.relayResolver = { [relays] id in try await relays.relay(id) }
        router.currentUserID = { [session] in session.user?.id }
    }

    static func live(configuration: AppConfiguration = .current) -> AppDependencies {
        switch configuration.backend {
        case .mock:
            return mock(configuration: configuration)
        case .supabase(let url, let anonKey):
            return supabase(configuration: configuration, url: url, anonKey: anonKey)
        }
    }

    /// The frontend-phase graph: everything in memory, persisted as JSON, with simulated server loops.
    static func mock(configuration: AppConfiguration) -> AppDependencies {
        let clock = AdjustableDateProvider()
        let media = LocalMediaStore.default()
        let sessionStore = UserDefaultsSessionStore()
        let persistence = MockPersistence.default()
        LaunchArguments.apply(sessionStore: sessionStore, persistence: persistence, clock: clock)
        let store = MockDataStore(clock: clock, media: media, rules: LaunchArguments.rules ?? configuration.rules, persistence: persistence)
        return AppDependencies(
            configuration: configuration, clock: clock, media: media, sessionStore: sessionStore,
            auth: MockAuthService(store: store, sessionStore: sessionStore, clock: clock),
            users: MockUserRepository(store: store, sessionStore: sessionStore),
            groups: MockGroupRepository(store: store),
            relays: MockRelayRepository(store: store),
            revealManifests: MockRevealManifestProvider(),
            changes: MockDataChangeSource(store: store),
            notifications: LocalNotificationService(),
            mockStore: store)
    }

    /// The real graph. Rules are enforced server-side; the client keeps `LocalMediaStore` as its capture/Reveal cache.
    static func supabase(configuration: AppConfiguration, url: URL, anonKey: String) -> AppDependencies {
        let clock = AdjustableDateProvider()
        let media = LocalMediaStore.default()
        let sessionStore = UserDefaultsSessionStore()
        let backend = SupabaseClientFactory.make(url: url, anonKey: anonKey)
        let users = SupabaseUserRepository(backend: backend, sessionStore: sessionStore, media: media, clock: clock)
        return AppDependencies(
            configuration: configuration, clock: clock, media: media, sessionStore: sessionStore,
            auth: SupabaseAuthService(backend: backend, users: users, sessionStore: sessionStore, clock: clock),
            users: users,
            groups: SupabaseGroupRepository(backend: backend),
            relays: SupabaseRelayRepository(backend: backend, media: media),
            revealManifests: SupabaseRevealManifestProvider(backend: backend, media: media),
            changes: SupabaseChangeSource(backend: backend),
            notifications: LocalNotificationService(),
            mockStore: nil,
            serverClock: ServerClock(backend: backend, clock: clock))
    }

    /// Runs once from the root view. Restores the session and starts the mock "server" loops or the real push/clock hooks.
    func bootstrap() async {
        let problems = configuration.validate()
        assert(problems.isEmpty, "Invalid configuration: \(problems)")
        AppDelegate.notificationTapHandler = { [router] info in router.handle(notificationUserInfo: info) }
        startMockServer()
        if let serverClock { Task { await serverClock.sync() } }
        await session.bootstrap()
        startRemotePush()
    }

    func handleForeground() {
        Task { [mockStore, serverClock] in
            await mockStore?.processDeadlines()
            await serverClock?.sync()
        }
    }

    // MARK: - Remote push (backend only)

    /// Asks APNs for a token and forwards it to `register_device_token` once a profile exists (the row references it).
    private func startRemotePush() {
        guard configuration.backend.isRemote else { return }
        AppDelegate.deviceTokenHandler = { [weak self] token in
            self?.deviceToken = token
            self?.flushDeviceToken()
        }
        session.stateDidChange = { [weak self] state in
            if state == .signedOut { self?.registeredDeviceToken = nil }
            self?.flushDeviceToken()
        }
        UIApplication.shared.registerForRemoteNotifications()
    }

    private func flushDeviceToken() {
        guard let token = deviceToken, session.state == .signedIn, registeredDeviceToken != token else { return }
        registeredDeviceToken = token
        Task { [users, weak self] in
            do { try await users.registerDeviceToken(token, environment: .current) }
            catch { self?.registeredDeviceToken = nil } // retried on the next sign-in or token refresh
        }
    }

    // MARK: - Mock server

    /// The mock equivalent of the backend's scheduled job (process expired Batons) and its push dispatcher.
    private func startMockServer() {
        guard let store = mockStore, deadlineTask == nil else { return }
        deadlineTask = Task { [weak self] in
            while !Task.isCancelled {
                await store.processDeadlines()
                try? await Task.sleep(for: .seconds(1))
                if self == nil { break }
            }
        }
        eventTask = Task { [weak self] in
            for await event in await store.events() {
                guard case .relay(let relay, let events) = event, let self else { continue }
                await self.dispatchNotifications(relay: relay, events: events)
            }
        }
    }

    /// Mirrors spec §15 copy. Only notifies about events that concern me; the backend sends real pushes instead.
    private func dispatchNotifications(relay: Relay, events: [RelayEvent]) async {
        guard let me = session.user?.id, let store = mockStore else { return }
        let prefs = await store.preferencesSnapshot()
        for event in events {
            switch event {
            case .batonReceived(let to, let from) where to == me && from != me:
                guard prefs.batonReceived else { continue }
                let name = from.flatMap { relay.participant($0)?.user.firstName } ?? "Someone"
                await notifications.scheduleLocal(title: "PASS", body: "🔥 \(name) passed you the Baton.", relayID: relay.id)
            case .rescueStarted(let who) where who == me:
                guard prefs.reminders else { continue }
                await notifications.scheduleLocal(title: "PASS", body: "🔥 Last chance — rescue the Relay. 15 minutes left.", relayID: relay.id)
            case .deferred(let who) where who == me:
                guard prefs.reminders else { continue }
                await notifications.scheduleLocal(title: "PASS", body: "You dropped the Baton 👀 You'll get one last chance later.", relayID: relay.id)
            case .onePersonLeft:
                guard prefs.relayProgress, relay.participant(me) != nil else { continue }
                await notifications.scheduleLocal(title: "PASS", body: "One person left until the Reveal.", relayID: relay.id)
            case .ended(let outcome):
                guard prefs.relayComplete, relay.participant(me) != nil else { continue }
                let body: String
                switch outcome {
                case .complete, .failedWithReveal: body = "🎉 Your Relay is ready."
                case .failed: body = "The Relay ended without a Reveal."
                case .cancelled: body = relay.endedReason ?? "The Relay ended."
                }
                await notifications.scheduleLocal(title: "PASS", body: body, relayID: relay.id)
            default:
                continue
            }
        }
    }
}

// MARK: - Environment access

private struct DependenciesKey: EnvironmentKey {
    static let defaultValue: AppDependencies? = nil
}

extension EnvironmentValues {
    var dependencies: AppDependencies? {
        get { self[DependenciesKey.self] }
        set { self[DependenciesKey.self] = newValue }
    }
}

extension View {
    func dependencies(_ deps: AppDependencies) -> some View {
        environment(\.dependencies, deps)
            .environment(deps.session)
            .environment(deps.router)
    }
}

/// Test and demo hooks read from the process arguments. Only honoured in DEBUG builds.
enum LaunchArguments {
    static var args: [String] { CommandLine.arguments }
    static var resetState: Bool { args.contains("-resetState") }
    static var demoSession: Bool { args.contains("-demoSession") }
    static var fastTimers: Bool { args.contains("-fastTimers") }
    static var rules: RelayRules? { fastTimers ? .demo : nil }

    static func apply(sessionStore: UserDefaultsSessionStore, persistence: MockPersistence, clock: AdjustableDateProvider) {
        #if DEBUG
        if resetState {
            sessionStore.wipeAll()
            persistence.wipe()
        }
        if demoSession {
            let user = User(id: MockFixtures.meID, displayName: "Khizar", colorHex: "#6B46FF", avatarFileName: nil,
                            memberSince: clock.now().addingTimeInterval(-40 * 86_400), dateOfBirth: nil)
            sessionStore.saveUser(user)
            sessionStore.saveSession(Session(userID: user.id, onboardingComplete: true))
            sessionStore.notificationPromptShown = true
        }
        #endif
    }
}
