import SwiftUI

/// Figma "Profile" + spec §25/§26: user info, groups, Notifications, Privacy, About, Support, invite code, Sign Out,
/// Delete Account. DEBUG builds add demo tools for the mock backend.
struct ProfileView: View {
    let deps: AppDependencies
    @Environment(AppRouter.self) private var router
    @Environment(AppSession.self) private var session
    @State private var groups: Loadable<[Group]> = .idle
    @State private var showSignOut = false
    @State private var showDelete = false
    @State private var deleteError: String?
    @State private var fastTimers = false

    var body: some View {
        PassScreen {
            VStack(spacing: 0) {
                PassNavRow(backLabel: "Home", onBack: router.pop)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        SectionLabel(label: "Your Groups")
                        groupsGrid.padding(.bottom, 24)
                        SectionLabel(label: "Settings")
                        settingsList.padding(.bottom, 24)
                        SectionLabel(label: "Account")
                        accountList
                        if deps.configuration.demoControlsEnabled, deps.mockStore != nil { demoSection }
                        Text("PASS \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") · No public profile. No followers. Just your crew.")
                            .inter(11).foregroundStyle(PassColor.text(0.2)).frame(maxWidth: .infinity).padding(.vertical, 24)
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        .task { await loadGroups() }
        .confirmationDialog("Sign out of PASS?", isPresented: $showSignOut, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) { Task { await session.signOut() } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Delete your account?", isPresented: $showDelete) {
            Button("Delete Account", role: .destructive) { Task { if !(await session.deleteAccount()) { deleteError = session.lastError?.userMessage } } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes your profile, your groups' memberships and your submissions. It can't be undone.")
        }
        .alert("Couldn't delete account", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(deleteError ?? "") }
    }

    private var header: some View {
        VStack(spacing: 0) {
            UserAvatarView(name: session.user?.displayName ?? "You", colorHex: session.user?.colorHex ?? "#6B46FF",
                           avatarFileName: session.user?.avatarFileName, size: 80)
                .padding(.bottom, 14)
            Text(session.user?.displayName ?? "You").outfit(22, .heavy, tracking: -0.5).foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            if let since = session.user?.memberSince {
                Text("Member since \(PassFormatters.memberSince.string(from: since))").inter(13).foregroundStyle(PassColor.text(0.38)).padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity).padding(.top, 16).padding(.bottom, 28)
    }

    @ViewBuilder
    private var groupsGrid: some View {
        switch groups {
        case .idle, .loading: ProgressView().tint(PassColor.text(0.5)).frame(maxWidth: .infinity).padding()
        case .failed(let e): ErrorStateView(message: e.userMessage) { Task { await loadGroups() } }.frame(height: 120)
        case .loaded(let gs):
            if gs.isEmpty {
                Text("No groups yet").inter(13).foregroundStyle(PassColor.text(0.3)).frame(maxWidth: .infinity).padding()
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(gs) { g in
                        Button { router.push(.groupDetail(g.id)) } label: {
                            VStack(spacing: 3) {
                                Text(g.emoji).font(.system(size: 20))
                                Text(g.name).outfit(13, .bold).foregroundStyle(.white).multilineTextAlignment(.center).lineLimit(2)
                                Text("\(g.memberCount) members").inter(11).foregroundStyle(PassColor.text(0.35))
                            }
                            .frame(maxWidth: .infinity).padding(.horizontal, 8).padding(.vertical, 12).passCard(radius: 14)
                        }
                        .buttonStyle(PressableRowStyle())
                    }
                }
            }
        }
    }

    private var settingsList: some View {
        SettingsGroup {
            SettingsRow(icon: "🔔", title: "Notifications") { router.push(.notificationSettings) }
            SettingsRow(icon: "🔒", title: "Privacy") { router.push(.privacySettings) }
            SettingsRow(icon: "👾", title: "About PASS") { router.push(.about) }
            SettingsRow(icon: "💬", title: "Support") { router.push(.support) }
            SettingsRow(icon: "🔗", title: "Got an invite code?", id: "settings.inviteCode", last: true) { router.push(.inviteCodeEntry) }
        }
    }

    private var accountList: some View {
        SettingsGroup {
            SettingsRow(icon: "🚪", title: "Sign Out", id: "settings.signOut", destructive: true) { showSignOut = true }
            SettingsRow(icon: "🗑️", title: "Delete Account", id: "settings.deleteAccount", destructive: true, last: true) { showDelete = true }
        }
    }

    private var demoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(label: "Demo tools (mock backend)").padding(.top, 24)
            SettingsGroup {
                SettingsRow(icon: "📨", title: "Simulate an incoming invite") {
                    Task { if let code = await deps.mockStore?.demoInviteCode() { router.fullScreen = .invite(code: code) } else { router.showToast("You're already in every demo group") } }
                }
                SettingsRow(icon: "⏱️", title: fastTimers ? "Fast timers: on (3 min / 1 min)" : "Fast timers: off (2 h / 15 min)") {
                    fastTimers.toggle()
                    Task { await deps.mockStore?.setRules(fastTimers ? .demo : .standard); router.showToast(fastTimers ? "New turns get 3-minute windows" : "Standard 2-hour windows") }
                }
                SettingsRow(icon: "♻️", title: "Reset demo data", last: true) {
                    Task { await deps.mockStore?.resetAll(keepUser: true); router.showToast("Demo data reset"); await loadGroups() }
                }
            }
            Text("Everything in this build runs against an in-app mock. Real sign-in, push and storage arrive with the backend.")
                .inter(11).foregroundStyle(PassColor.text(0.25))
        }
    }

    private func loadGroups() async {
        if groups.value == nil { groups = .loading }
        do { groups = .loaded(try await deps.groups.groups()) }
        catch { let e = AppError.wrap(error); if !e.isCancellation, groups.value == nil { groups = .failed(e) } }
    }
}

struct SettingsGroup<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .passCard(radius: 16)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct SettingsRow: View {
    let icon: String
    let title: String
    var id: String? = nil
    var subtitle: String? = nil
    var destructive = false
    var last = false
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 12) {
                    Text(icon).font(.system(size: 18)).frame(width: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).inter(15, .medium).foregroundStyle(destructive ? PassColor.red : .white)
                        if let subtitle { Text(subtitle).inter(12).foregroundStyle(PassColor.text(0.35)) }
                    }
                    Spacer()
                    if !destructive { ChevronRight() }
                }
                .padding(.horizontal, 18).padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableRowStyle())
            .accessibilityIdentifier(id ?? "settings.\(title.lowercased().replacingOccurrences(of: " ", with: "-"))")
            if !last { Rectangle().fill(PassColor.text(0.05)).frame(height: 1).accessibilityHidden(true) }
        }
    }
}
