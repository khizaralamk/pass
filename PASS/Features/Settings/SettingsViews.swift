import SwiftUI
import UIKit

/// Spec §25 notification settings: per-event toggles (mock-persisted) + the system permission state.
struct NotificationSettingsView: View {
    let deps: AppDependencies
    @Environment(AppRouter.self) private var router
    @State private var prefs: NotificationPreferences?
    @State private var status: NotificationAuthorization = .notDetermined
    @State private var error: String?

    var body: some View {
        PassScreen {
            VStack(spacing: 0) {
                PassNavRow(backLabel: "Back", onBack: router.pop)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Notifications").outfit(36, .black, tracking: -1.5).foregroundStyle(.white).padding(.bottom, 6).accessibilityAddTraits(.isHeader)
                        Text("PASS only sends what moves the Relay forward.").inter(14).foregroundStyle(PassColor.text(0.4)).padding(.bottom, 22)
                        systemStatus.padding(.bottom, 18)
                        if prefs != nil {
                            SectionLabel(label: "Send me")
                            VStack(spacing: 0) {
                                toggle("🔥", "Baton received", "“Maya passed you the Baton.”", binding(\.batonReceived))
                                toggle("⏳", "Reminders", "“Your Baton is waiting.” · “Don't drop the Baton 👀”", binding(\.reminders))
                                toggle("👀", "Relay progress", "“One person left until the Reveal.”", binding(\.relayProgress))
                                toggle("🎉", "Relay complete", "“Your Relay is ready.”", binding(\.relayComplete), last: true)
                            }
                            .passCard(radius: 16).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        } else if let error {
                            ErrorStateView(message: error) { Task { await load() } }.frame(height: 160)
                        } else {
                            ProgressView().tint(PassColor.text(0.5)).frame(maxWidth: .infinity).padding()
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in Task { status = await deps.notifications.authorizationStatus() } }
    }

    private var systemStatus: some View {
        HStack(spacing: 12) {
            Text(status == .authorized ? "✅" : status == .denied ? "🔕" : "🔔").font(.system(size: 20))
            VStack(alignment: .leading, spacing: 2) {
                Text(status == .authorized ? "Notifications are on" : status == .denied ? "Notifications are off" : "Notifications not set up")
                    .outfit(15, .bold).foregroundStyle(.white)
                Text(status == .authorized ? "You'll know the moment it's your turn." : status == .denied ? "Turn them on in iOS Settings so you don't drop the Baton." : "Allow notifications to hear when it's your turn.")
                    .inter(12).foregroundStyle(PassColor.text(0.4))
            }
            Spacer()
            if status == .denied {
                Button("Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                    .font(PassFont.inter(13, .semibold)).foregroundStyle(PassColor.violet)
            } else if status == .notDetermined {
                Button("Allow") { Task { _ = await deps.notifications.requestAuthorization(); status = await deps.notifications.authorizationStatus() } }
                    .font(PassFont.inter(13, .semibold)).foregroundStyle(PassColor.violet)
            }
        }
        .padding(16).passCard(radius: 16)
    }

    private func toggle(_ icon: String, _ title: String, _ sub: String, _ binding: Binding<Bool>, last: Bool = false) -> some View {
        VStack(spacing: 0) {
            Toggle(isOn: binding) {
                HStack(spacing: 12) {
                    Text(icon).font(.system(size: 18)).frame(width: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).inter(15, .medium).foregroundStyle(.white)
                        Text(sub).inter(12).foregroundStyle(PassColor.text(0.35))
                    }
                }
            }
            .tint(PassColor.violet)
            .padding(.horizontal, 18).padding(.vertical, 12)
            if !last { Rectangle().fill(PassColor.text(0.05)).frame(height: 1) }
        }
    }

    private func load() async {
        error = nil
        status = await deps.notifications.authorizationStatus()
        do { prefs = try await deps.users.notificationPreferences() } catch { self.error = AppError.wrap(error).userMessage }
    }

    private func binding(_ keyPath: WritableKeyPath<NotificationPreferences, Bool>) -> Binding<Bool> {
        Binding(
            get: { prefs?[keyPath: keyPath] ?? false },
            set: { value in
                guard var p = prefs else { return }
                let previous = p
                p[keyPath: keyPath] = value
                prefs = p
                Task {
                    do { try await deps.users.updateNotificationPreferences(p) }
                    catch { prefs = previous; router.showToast(AppError.wrap(error).userMessage) }
                }
            })
    }
}

/// Spec §26 privacy: blocked users (unblock), what PASS keeps private, policy link.
struct PrivacySettingsView: View {
    let deps: AppDependencies
    @Environment(AppRouter.self) private var router
    @State private var blocked: Loadable<[UserSummary]> = .idle

    var body: some View {
        PassScreen {
            VStack(spacing: 0) {
                PassNavRow(backLabel: "Back", onBack: router.pop)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Privacy").outfit(36, .black, tracking: -1.5).foregroundStyle(.white).padding(.bottom, 6).accessibilityAddTraits(.isHeader)
                        Text("PASS has no public profiles, no followers and no discovery.").inter(14).foregroundStyle(PassColor.text(0.4)).padding(.bottom, 22)
                        VStack(alignment: .leading, spacing: 12) {
                            fact("🔒", "Submissions are hidden from everyone, including your group, until the Reveal.")
                            fact("👥", "Only members of a group can see its name, members, Relays and Reveals.")
                            fact("🎂", "Your date of birth is used once to confirm you're 16+. It's never shown.")
                            fact("🗑️", "Deleting your account removes your profile and submissions.")
                        }
                        .padding(18).passCard(radius: 16).padding(.bottom, 24)
                        SectionLabel(label: "Blocked users")
                        blockedList.padding(.bottom, 24)
                        Link(destination: deps.configuration.privacyPolicyURL) {
                            HStack { Text("Read the Privacy Policy").inter(15, .medium).foregroundStyle(.white); Spacer(); Image(systemName: "arrow.up.right").foregroundStyle(PassColor.text(0.3)) }
                                .padding(.horizontal, 18).padding(.vertical, 14).passCard(radius: 16)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    private var blockedList: some View {
        switch blocked {
        case .idle, .loading: ProgressView().tint(PassColor.text(0.5)).frame(maxWidth: .infinity).padding()
        case .failed(let e): ErrorStateView(message: e.userMessage) { Task { await load() } }.frame(height: 120)
        case .loaded(let users):
            if users.isEmpty {
                Text("You haven't blocked anyone. Block someone from a group's member list.").inter(13).foregroundStyle(PassColor.text(0.3))
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading).passCard(radius: 14)
            } else {
                VStack(spacing: 8) {
                    ForEach(users) { u in
                        HStack(spacing: 12) {
                            AvatarView(initials: u.initials, color: Color(hexString: u.colorHex), size: 36)
                            Text(u.displayName).outfit(15, .bold).foregroundStyle(.white)
                            Spacer()
                            Button("Unblock") { Task { await unblock(u) } }.font(PassFont.inter(13, .semibold)).foregroundStyle(PassColor.violet)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10).passCard(radius: 14)
                    }
                }
            }
        }
    }

    private func fact(_ emoji: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(emoji).font(.system(size: 16))
            Text(text).inter(13).foregroundStyle(PassColor.text(0.6)).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func load() async {
        if blocked.value == nil { blocked = .loading }
        do { blocked = .loaded(try await deps.users.blockedUsers()) }
        catch { let e = AppError.wrap(error); if !e.isCancellation, blocked.value == nil { blocked = .failed(e) } }
    }

    private func unblock(_ u: UserSummary) async {
        do { try await deps.users.unblock(u.id); router.showToast("\(u.firstName) unblocked"); await load() }
        catch { router.showToast(AppError.wrap(error).userMessage) }
    }
}

struct AboutView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.dependencies) private var deps

    var body: some View {
        PassScreen {
            VStack(spacing: 0) {
                PassNavRow(backLabel: "Back", onBack: router.pop)
                ScrollView {
                    VStack(alignment: .center, spacing: 0) {
                        BrandTile(size: 72).padding(.top, 10).padding(.bottom, 18)
                        Text("PASS").outfit(44, .black, tracking: -2.5).foregroundStyle(.white)
                        Text("Private challenges. Group reveals.").inter(14).foregroundStyle(PassColor.text(0.38)).padding(.bottom, 26)
                        VStack(alignment: .leading, spacing: 14) {
                            step("1", "Start a Challenge with your crew.")
                            step("2", "One person holds the Baton at a time: 2 hours to post a photo or a 4-second video, then pass it on.")
                            step("3", "Everything stays hidden until everyone's done.")
                            step("4", "PASS builds the Reveal. Watch it, share it, start another.")
                        }
                        .padding(18).frame(maxWidth: .infinity, alignment: .leading).passCard(radius: 16).padding(.bottom, 18)
                        if let deps {
                            SettingsGroup {
                                SettingsRow(icon: "📄", title: "Terms of Use") { UIApplication.shared.open(deps.configuration.termsURL) }
                                SettingsRow(icon: "🔒", title: "Privacy Policy", last: true) { UIApplication.shared.open(deps.configuration.privacyPolicyURL) }
                            }
                        }
                        Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))")
                            .inter(12).foregroundStyle(PassColor.text(0.25)).padding(.top, 20)
                        Text("No public profile. No followers. Just your crew.").inter(12).foregroundStyle(PassColor.text(0.18)).padding(.top, 4)
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }

    private func step(_ n: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(n).outfit(12, .bold).foregroundStyle(PassColor.violet).frame(width: 24, height: 24).background(PassColor.violet.opacity(0.15), in: Circle())
            Text(text).inter(14).foregroundStyle(PassColor.text(0.65)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Spec §25/§26 support/contact: email with a prefilled subject, copy address.
struct SupportView: View {
    let deps: AppDependencies
    @Environment(AppRouter.self) private var router
    @State private var copied = false

    var body: some View {
        PassScreen {
            VStack(spacing: 0) {
                PassNavRow(backLabel: "Back", onBack: router.pop)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Support").outfit(36, .black, tracking: -1.5).foregroundStyle(.white).padding(.bottom, 6).accessibilityAddTraits(.isHeader)
                        Text("Something broken? Someone being awful? Tell us. We reply within 24 hours.").inter(14).foregroundStyle(PassColor.text(0.4)).padding(.bottom, 22)
                        VStack(spacing: 10) {
                            Eyebrow(text: "Email", size: 12, opacity: 0.35)
                            Text(deps.configuration.supportEmail).outfit(20, .heavy, tracking: -0.5).foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 20).passCard().padding(.bottom, 12)
                        PassButton(title: "✉️ Email support") {
                            let subject = "PASS support (\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"))".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                            if let url = URL(string: "mailto:\(deps.configuration.supportEmail)?subject=\(subject)") { UIApplication.shared.open(url) }
                        }
                        .padding(.bottom, 10)
                        PassButton(title: copied ? "✓ Copied" : "Copy email address", variant: .surface) {
                            UIPasteboard.general.string = deps.configuration.supportEmail
                            withAnimation { copied = true }
                            Task { try? await Task.sleep(for: .seconds(2)); withAnimation { copied = false } }
                        }
                        .padding(.bottom, 22)
                        HStack(alignment: .top, spacing: 10) {
                            Text("🚩").font(.system(size: 16))
                            Text("To report a person or a Reveal, use Report from a group's member list or the Reveal screen. Reports are reviewed within 24 hours.")
                                .inter(13).foregroundStyle(PassColor.text(0.5)).lineSpacing(3)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12).passCard(radius: 14)
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }
}
