import Foundation

/// In-memory "backend" for the frontend phase. Holds all mock state, applies `RelayEngine`, persists itself as JSON so a
/// demo survives relaunches, and broadcasts changes. Everything here is replaced by the real backend; nothing in the UI
/// depends on this type directly (views talk to the protocols in Data/Protocols).
actor MockDataStore {
    struct State: Codable {
        var users: [UserID: User] = [:]
        var groups: [GroupID: Group] = [:]
        var relays: [RelayID: Relay] = [:]
        var challenges: [Challenge] = []
        var reports: [Report] = []
        var blocked: Set<UserID> = []
        var preferences = NotificationPreferences()
        var joinPoolIndex = 0
        var seeded = false
    }

    enum Event: Sendable {
        case data(DataChange)
        case relay(Relay, [RelayEvent])
    }

    private(set) var state = State()
    private(set) var currentUserID: UserID?
    private(set) var rules: RelayRules
    private let clock: any DateProvider
    private let media: any MediaStore
    private let persistence: MockPersistence?
    private var continuations: [UUID: AsyncStream<Event>.Continuation] = [:]

    /// Simulated network latency and an injectable failure, used by demo controls and tests.
    private(set) var latency: Duration = .milliseconds(220)
    private(set) var failNextRequest = false

    func setLatency(_ d: Duration) { latency = d }
    func setFailNextRequest(_ fail: Bool) { failNextRequest = fail }

    init(clock: any DateProvider, media: any MediaStore, rules: RelayRules = .standard, persistence: MockPersistence? = nil) {
        self.clock = clock
        self.media = media
        self.rules = rules
        self.persistence = persistence
        if let saved = persistence?.load() { state = saved }
    }

    // MARK: Events

    func events() -> AsyncStream<Event> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id) }
            }
        }
    }

    private func removeContinuation(_ id: UUID) { continuations[id] = nil }

    private func emit(_ event: Event) {
        for c in continuations.values { c.yield(event) }
    }

    private func commit(_ change: DataChange) {
        persistence?.save(state)
        emit(.data(change))
    }

    // MARK: Simulation of a request

    private func request() async throws {
        if latency > .zero { try await Task.sleep(for: latency) }
        try Task.checkCancellation()
        if failNextRequest {
            failNextRequest = false
            throw AppError.network
        }
    }

    private func me() throws -> UserID {
        guard let id = currentUserID else { throw AppError.unauthorized }
        return id
    }

    // MARK: Session & seeding

    func setRules(_ rules: RelayRules) { self.rules = rules }

    func setCurrentUser(_ user: User?) {
        currentUserID = user?.id
        if let user { state.users[user.id] = user }
        if user != nil { seedIfNeeded() }
        persistence?.save(state)
    }

    private func seedIfNeeded() {
        guard !state.seeded, let id = currentUserID, let me = state.users[id] else { return }
        let now = clock.now()
        state.challenges = MockFixtures.challenges
        for g in MockFixtures.groups(me: me.summary, now: now) { state.groups[g.id] = g }
        for g in state.groups.values { for m in g.members where m.id != id { state.users[m.id] = User(id: m.id, displayName: m.user.displayName, colorHex: m.user.colorHex, avatarFileName: nil, memberSince: m.joinedAt, dateOfBirth: nil) } }
        seedRelays(now: now, me: me.summary)
        state.seeded = true
    }

    /// Active relay in Friday (Jake went, the Baton is with me) and a history of completed relays with fixture photos.
    private func seedRelays(now: Date, me: UserSummary) {
        guard let friday = state.groups[MockFixtures.fridayID], let court = state.groups[MockFixtures.courtID],
              let brunch = state.groups[MockFixtures.brunchID] else { return }
        let hour: TimeInterval = 3600, day: TimeInterval = 86_400

        func completed(_ group: Group, _ title: String, daysAgo: Double, seed: Int) -> Relay {
            let start = now.addingTimeInterval(-daysAgo * day)
            var r = try! RelayEngine.start(group: group, challengeTitle: title, creator: group.createdBy, hasActiveRelay: false, now: start, rules: rules)
            var t = start
            var order = group.membersByJoinOrder.map(\.id)
            order.removeAll { $0 == group.createdBy }
            order.insert(group.createdBy, at: 0)
            for (i, uid) in order.enumerated() {
                let member = group.member(uid)!.user
                t = t.addingTimeInterval(25 * 60)
                let file = "fixture-\(member.id.raw)-\(seed + i).jpg" // generated lazily by FixtureMediaFactory
                (r, _) = try! RelayEngine.submit(r, by: uid, mediaType: .photo, fileName: file, durationMs: nil, now: t, rules: rules)
                if i + 1 < order.count {
                    (r, _) = try! RelayEngine.pass(r, from: uid, to: order[i + 1], now: t.addingTimeInterval(60), rules: rules)
                }
            }
            return r
        }

        let history = [
            completed(friday, "Show your view right now", daysAgo: 2, seed: 10),
            completed(friday, "Find something red", daysAgo: 6, seed: 20),
            completed(court, "Show your current fit", daysAgo: 4, seed: 30),
        ]
        for r in history { state.relays[r.id] = r }

        // Friday: live relay, Jake submitted 40 min ago and passed to me (1h 58m left, as in the Figma).
        let fridayStart = now.addingTimeInterval(-45 * 60)
        var live = try! RelayEngine.start(group: friday, challengeTitle: "Worst Selfie", creator: MockFixtures.jake.id, hasActiveRelay: false, now: fridayStart, rules: rules)
        (live, _) = try! RelayEngine.submit(live, by: MockFixtures.jake.id, mediaType: .photo, fileName: "fixture-jake-1.jpg", durationMs: nil, now: fridayStart.addingTimeInterval(5 * 60), rules: rules)
        (live, _) = try! RelayEngine.pass(live, from: MockFixtures.jake.id, to: me.id, now: now.addingTimeInterval(-2 * 60 - (hour * 0.0)), rules: rules)
        state.relays[live.id] = live

        // Brunch (not my group yet): Sam went, Priya has the Baton. Seen in the invite preview.
        let brunchStart = now.addingTimeInterval(-30 * 60)
        var b = try! RelayEngine.start(group: brunch, challengeTitle: "What Are You Eating?", creator: MockFixtures.sam.id, hasActiveRelay: false, now: brunchStart, rules: rules)
        (b, _) = try! RelayEngine.submit(b, by: MockFixtures.sam.id, mediaType: .photo, fileName: "fixture-sam-2.jpg", durationMs: nil, now: brunchStart.addingTimeInterval(4 * 60), rules: rules)
        (b, _) = try! RelayEngine.pass(b, from: MockFixtures.sam.id, to: MockFixtures.priya.id, now: brunchStart.addingTimeInterval(5 * 60), rules: rules)
        state.relays[b.id] = b
    }

    /// Full reset to fixtures (DEBUG demo control and "Delete account").
    func resetAll(keepUser: Bool) {
        let user = currentUserID.flatMap { state.users[$0] }
        state = State()
        if keepUser, let user { state.users[user.id] = user; seedIfNeeded() } else { currentUserID = nil }
        persistence?.save(state)
        emit(.data(.all))
    }

    // MARK: Users

    func currentUser() async throws -> User {
        try await request()
        let uid = try me()
        guard let u = state.users[uid] else { throw AppError.unauthorized }
        return u
    }

    func updateCurrentUser(_ change: (inout User) -> Void) async throws -> User {
        try await request()
        let id = try me()
        guard var u = state.users[id] else { throw AppError.unauthorized }
        change(&u)
        state.users[id] = u
        // Keep the name/colour in sync everywhere it is denormalised.
        for (gid, var g) in state.groups {
            if let i = g.members.firstIndex(where: { $0.id == id }) { g.members[i].user = u.summary; state.groups[gid] = g }
        }
        for (rid, var r) in state.relays {
            if let i = r.participants.firstIndex(where: { $0.id == id }) { r.participants[i].user = u.summary; state.relays[rid] = r }
        }
        commit(.user)
        return u
    }

    func preferences() async throws -> NotificationPreferences { try await request(); return state.preferences }
    func setPreferences(_ p: NotificationPreferences) async throws { try await request(); state.preferences = p; commit(.user) }
    func preferencesSnapshot() -> NotificationPreferences { state.preferences }

    func blockedUsers() async throws -> [UserSummary] {
        try await request()
        return state.blocked.compactMap { state.users[$0]?.summary }.sorted { $0.displayName < $1.displayName }
    }
    func block(_ id: UserID) async throws { try await request(); state.blocked.insert(id); commit(.user) }
    func unblock(_ id: UserID) async throws { try await request(); state.blocked.remove(id); commit(.user) }

    func report(target: ReportTarget, reason: ReportReason, details: String) async throws {
        try await request()
        let uid = try me()
        state.reports.append(Report(id: .new(), reporterID: uid, target: target, reason: reason, details: details, createdAt: clock.now()))
        persistence?.save(state)
    }

    // MARK: Groups

    private func myGroups() throws -> [Group] {
        let id = try me()
        return state.groups.values.filter { $0.contains(id) }.sorted { $0.createdAt < $1.createdAt }
    }

    func groups() async throws -> [Group] { try await request(); return try myGroups() }

    func group(_ id: GroupID) async throws -> Group {
        try await request()
        guard let g = state.groups[id], g.contains(try me()) else { throw AppError.notFound("Group") }
        return g
    }

    func createGroup(name: String, emoji: String) async throws -> Group {
        try await request()
        let id = try me()
        guard let u = state.users[id] else { throw AppError.unauthorized }
        var code = InviteCode.generate()
        while state.groups.values.contains(where: { $0.inviteCode == code }) { code = InviteCode.generate() }
        let now = clock.now()
        let g = Group(id: .new(), name: name, emoji: emoji, inviteCode: code, createdBy: id, createdAt: now,
                      members: [GroupMember(user: u.summary, role: .creator, joinedAt: now)], stats: GroupStats())
        state.groups[g.id] = g
        commit(.groups)
        return g
    }

    func groupByCode(_ code: String) -> Group? {
        state.groups.values.first { $0.inviteCode.caseInsensitiveCompare(code) == .orderedSame }
    }

    func invitePreview(code: String) async throws -> InvitePreview {
        try await request()
        guard let g = groupByCode(code), let creator = g.member(g.createdBy)?.user else {
            throw AppError.notFound("That invite")
        }
        if state.blocked.contains(g.createdBy) { throw AppError.permissionDenied("You've blocked the person who created this group.") }
        return InvitePreview(group: g, invitedBy: creator, activeRelay: activeRelay(in: g.id))
    }

    func joinGroup(code: String) async throws -> Group {
        try await request()
        let id = try me()
        guard var g = groupByCode(code), let u = state.users[id] else { throw AppError.notFound("That invite") }
        if g.contains(id) { return g }
        guard g.memberCount < rules.maxMembers else {
            throw AppError.conflict("\(g.name) is full. PASS groups hold up to \(rules.maxMembers) people.")
        }
        g.members.append(GroupMember(user: u.summary, role: .member, joinedAt: clock.now()))
        state.groups[g.id] = g
        commit(.groups)
        return g
    }

    func leaveGroup(_ gid: GroupID) async throws {
        try await request()
        let id = try me()
        try removeMember(id, from: gid, reason: "Relay ended because a member left the group.")
    }

    func removeMember(_ userID: UserID, from gid: GroupID, by actor: UserID? = nil) async throws {
        try await request()
        let me = try me()
        guard let g = state.groups[gid] else { throw AppError.notFound("Group") }
        guard g.isCreator(me) else { throw AppError.permissionDenied("Only the person who created the group can remove members.") }
        guard userID != me else { throw AppError.validation("Use Leave Group to remove yourself.") }
        try removeMember(userID, from: gid, reason: "Relay ended because a member left the group.")
    }

    /// Spec §17: a participating member leaving cancels the active relay and removes its media.
    private func removeMember(_ userID: UserID, from gid: GroupID, reason: String) throws {
        guard var g = state.groups[gid], g.contains(userID) else { throw AppError.notFound("Group") }
        g.members.removeAll { $0.id == userID }
        if g.createdBy == userID, let next = g.membersByJoinOrder.first {
            g.createdBy = next.id
            g.members[g.members.firstIndex(where: { $0.id == next.id })!].role = .creator
        }
        if g.members.isEmpty { state.groups[gid] = nil } else { state.groups[gid] = g }
        if var r = activeRelay(in: gid), r.participant(userID) != nil {
            let files = r.participants.compactMap(\.submission?.fileName)
            let events: [RelayEvent]
            (r, events) = RelayEngine.cancel(r, reason: reason, now: clock.now())
            state.relays[r.id] = r
            if var gg = state.groups[gid] { gg.stats.apply(.cancelled); state.groups[gid] = gg }
            for f in files where !f.hasPrefix("fixture-") { media.delete(fileName: f) }
            emit(.relay(r, events))
        }
        commit(.all)
    }

    // MARK: Relays

    func activeRelay(in gid: GroupID) -> Relay? {
        state.relays.values.first { $0.groupID == gid && $0.isActive }
    }

    func activeRelays() async throws -> [Relay] {
        try await request()
        let mine = try myGroups().map(\.id)
        return state.relays.values.filter { $0.isActive && mine.contains($0.groupID) }.sorted { $0.createdAt > $1.createdAt }
    }

    func relay(_ id: RelayID) async throws -> Relay {
        try await request()
        let uid = try me()
        guard let r = state.relays[id], let g = state.groups[r.groupID], g.contains(uid) || r.participant(uid) != nil else {
            throw AppError.notFound("Relay")
        }
        return r
    }

    func relaySnapshot(_ id: RelayID) -> Relay? { state.relays[id] }

    func history(groupID: GroupID) async throws -> [Relay] {
        try await request()
        _ = try me()
        return state.relays.values.filter { $0.groupID == groupID && !$0.isActive }.sorted { ($0.endedAt ?? $0.createdAt) > ($1.endedAt ?? $1.createdAt) }
    }

    func challenges() async throws -> [Challenge] { try await request(); return state.challenges }

    func startRelay(groupID: GroupID, challengeTitle: String) async throws -> Relay {
        try await request()
        let id = try me()
        guard let g = state.groups[groupID], g.contains(id) else { throw AppError.notFound("Group") }
        do {
            let r = try RelayEngine.start(group: g, challengeTitle: challengeTitle, creator: id,
                                          hasActiveRelay: activeRelay(in: groupID) != nil, now: clock.now(), rules: rules)
            state.relays[r.id] = r
            commit(.relays)
            return r
        } catch RelayEngineError.groupHasActiveRelay {
            throw AppError.conflict("This group already has an active Relay.")
        } catch RelayEngineError.groupTooSmall(let needed) {
            throw AppError.validation("Invite at least \(needed) more friend\(needed == 1 ? "" : "s") to start a Relay.")
        }
    }

    func submit(relayID: RelayID, media captured: CapturedMedia) async throws -> Relay {
        try await request()
        let id = try me()
        guard let r = state.relays[relayID] else { throw AppError.notFound("Relay") }
        let fileName = try media.importFile(at: captured.fileURL, preferredExtension: captured.type == .photo ? "jpg" : "mov")
        return try apply(relayID: relayID) { relay in
            try RelayEngine.submit(relay, by: id, mediaType: captured.type, fileName: fileName,
                                   durationMs: captured.durationMs, now: clock.now(), rules: rules)
        }
    }

    func passBaton(relayID: RelayID, to: UserID) async throws -> Relay {
        try await request()
        let id = try me()
        return try apply(relayID: relayID) { relay in
            try RelayEngine.pass(relay, from: id, to: to, now: clock.now(), rules: rules)
        }
    }

    /// Runs an engine transition, stores the result, updates group stats on an ending and broadcasts events.
    @discardableResult
    private func apply(relayID: RelayID, _ transition: (Relay) throws -> (Relay, [RelayEvent])) throws -> Relay {
        guard let before = state.relays[relayID] else { throw AppError.notFound("Relay") }
        let (after, events): (Relay, [RelayEvent])
        do { (after, events) = try transition(before) } catch let e as RelayEngineError { throw map(e) }
        state.relays[relayID] = after
        for case .ended(let outcome) in events {
            if var g = state.groups[after.groupID] { g.stats.apply(outcome); state.groups[after.groupID] = g }
        }
        commit(.relays)
        if !events.isEmpty { emit(.relay(after, events)) }
        return after
    }

    private func map(_ e: RelayEngineError) -> AppError {
        switch e {
        case .notActive: return .conflict("This Relay has already ended.")
        case .notHolder: return .conflict("The Baton isn't with you right now.")
        case .alreadySubmitted: return .conflict("Your submission is already locked in.")
        case .mustSubmitFirst: return .conflict("Submit your photo or video before passing the Baton.")
        case .notEligible: return .conflict("That member can't receive the Baton right now.")
        case .groupTooSmall(let n): return .validation("Invite at least \(n) more friend\(n == 1 ? "" : "s") to start a Relay.")
        case .groupHasActiveRelay: return .conflict("This group already has an active Relay.")
        }
    }

    // MARK: Deadlines (what the server cron does)

    /// Applies expirations to every active relay. Safe to call often; does nothing when no deadline has passed.
    func processDeadlines() {
        let now = clock.now()
        for r in state.relays.values where r.isActive {
            guard let t = r.currentTurn, t.deadline <= now else { continue }
            try? apply(relayID: r.id) { RelayEngine.processDeadlines($0, now: now, rules: rules) }
        }
    }

    // MARK: Demo controls (DEBUG only; see Documentation/MOCK-DATA.md)

    /// The current (non-me) holder submits a fixture photo and passes on: to me if I'm eligible, else the earliest member.
    func simulateHolderTurn(relayID: RelayID, fixtureFileName: @MainActor (UserSummary, Int) -> String) async throws {
        guard let r = state.relays[relayID], r.isActive, let holder = r.holder, holder.id != currentUserID else { return }
        let seed = Int(clock.now().timeIntervalSince1970) % 1000
        let file = await fixtureFileName(holder.user, seed)
        let now = clock.now()
        var after = try apply(relayID: relayID) { try RelayEngine.submit($0, by: holder.id, mediaType: .photo, fileName: file, durationMs: nil, now: now, rules: rules) }
        guard after.isActive, after.isHolder(holder.id) else { return }
        let eligible = RelayEngine.eligibleNext(after, excluding: holder.id)
        guard let next = eligible.first(where: { $0.id == currentUserID }) ?? eligible.first else { return }
        after = try apply(relayID: relayID) { try RelayEngine.pass($0, from: holder.id, to: next.id, now: now.addingTimeInterval(1), rules: rules) }
    }

    /// Expires the current turn right now (drop or rescue miss).
    func simulateExpiry(relayID: RelayID) throws {
        guard var r = state.relays[relayID], r.isActive, let i = r.turns.lastIndex(where: { $0.isOpen }) else { return }
        r.turns[i].deadline = clock.now()
        state.relays[relayID] = r
        processDeadlines()
    }

    /// Adds the next fixture person to a group (to reach 3 members, or to test the 7 cap).
    func simulateJoin(groupID: GroupID) async throws -> UserSummary {
        try await request()
        guard var g = state.groups[groupID] else { throw AppError.notFound("Group") }
        guard g.memberCount < rules.maxMembers else { throw AppError.conflict("\(g.name) is full (\(rules.maxMembers) members).") }
        let pool = MockFixtures.joinPool
        var candidate: UserSummary?
        for _ in 0..<pool.count {
            let c = pool[state.joinPoolIndex % pool.count]
            state.joinPoolIndex += 1
            if !g.contains(c.id) { candidate = c; break }
        }
        guard let u = candidate else { throw AppError.conflict("No more demo friends available.") }
        state.users[u.id] = User(id: u.id, displayName: u.displayName, colorHex: u.colorHex, avatarFileName: nil, memberSince: clock.now(), dateOfBirth: nil)
        g.members.append(GroupMember(user: u, role: .member, joinedAt: clock.now()))
        state.groups[groupID] = g
        commit(.groups)
        return u
    }

    /// A member other than me leaves the group (cancels an active relay, spec §17).
    func simulateMemberLeaves(groupID: GroupID) throws {
        guard let g = state.groups[groupID], let victim = g.members.first(where: { $0.id != currentUserID }) else { return }
        try removeMember(victim.id, from: groupID, reason: "Relay ended because a member left the group.")
    }

    /// Code of a group I'm not in (for testing the invite flow).
    func demoInviteCode() -> String? {
        guard let id = currentUserID else { return nil }
        return state.groups.values.first { !$0.contains(id) }?.inviteCode
    }
}

/// JSON persistence of the mock state in Application Support. Deleted by "Reset demo data" or by reinstalling.
struct MockPersistence: Sendable {
    let fileURL: URL

    static func `default`() -> MockPersistence {
        let dir = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return MockPersistence(fileURL: dir.appendingPathComponent("MockState.json"))
    }

    func load() -> MockDataStore.State? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(MockDataStore.State.self, from: data)
    }

    func save(_ state: MockDataStore.State) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func wipe() { try? FileManager.default.removeItem(at: fileURL) }
}
