import SwiftUI

/// Figma S2 (Invite) → S3 (Join Group), presented full screen over Home so an invited user never lands on a generic
/// Home first (spec §3). Handles: unknown code, already a member, group full, blocked creator.
@MainActor
@Observable
final class InviteViewModel {
    enum Step { case invite, join }
    let code: String
    private(set) var preview: Loadable<InvitePreview> = .idle
    var step: Step = .invite
    private(set) var isJoining = false
    var joinError: String?
    private let deps: AppDependencies

    init(code: String, deps: AppDependencies) {
        self.code = code
        self.deps = deps
    }

    var me: UserID? { deps.session.user?.id }
    var alreadyMember: Bool { if let me, let g = preview.value?.group { return g.contains(me) } else { return false } }

    func load() async {
        if preview.value == nil { preview = .loading }
        do { preview = .loaded(try await deps.groups.invitePreview(code: code)) }
        catch { let e = AppError.wrap(error); if !e.isCancellation { preview = .failed(e) } }
    }

    /// Joins, closes the cover and lands on the group (or straight on the Baton if it is already mine, as in the Figma).
    func join() async {
        guard !isJoining else { return }
        isJoining = true
        joinError = nil
        defer { isJoining = false }
        do {
            let group = try await deps.groups.joinGroup(code: code)
            Haptics.success()
            let relays = (try? await deps.relays.activeRelays()) ?? []
            deps.router.fullScreen = nil
            if let relay = relays.first(where: { $0.groupID == group.id }), let me, relay.participant(me) != nil {
                deps.router.show(relay: relay)
            } else {
                deps.router.replaceStack(with: [.groupDetail(group.id)])
            }
        } catch {
            let e = AppError.wrap(error)
            if !e.isCancellation { joinError = e.userMessage }
        }
    }

    func dismiss() { deps.router.fullScreen = nil }
    func openGroup() {
        guard let g = preview.value?.group else { return dismiss() }
        deps.router.fullScreen = nil
        deps.router.replaceStack(with: [.groupDetail(g.id)])
    }
}

struct InviteFlowView: View {
    @State var model: InviteViewModel

    var body: some View {
        PassScreen {
            switch model.preview {
            case .idle, .loading:
                VStack { PassNavRow(backLabel: "Close", onBack: model.dismiss); LoadingStateView(text: "Opening your invite…") }
            case .failed(let e):
                VStack {
                    PassNavRow(backLabel: "Close", onBack: model.dismiss)
                    ErrorStateView(message: e == .notFound("That invite") ? "That invite code doesn't match any group. Check the code and try again." : e.userMessage,
                                   retryTitle: "Try again") { Task { await model.load() } }
                }
            case .loaded(let preview):
                if model.alreadyMember {
                    alreadyMember(preview)
                } else if model.step == .invite {
                    InviteScreen(preview: preview, onClose: model.dismiss) { withAnimation(PassMotion.screenIn) { model.step = .join } }
                } else {
                    JoinScreen(model: model, preview: preview)
                }
            }
        }
        .task { await model.load() }
    }

    private func alreadyMember(_ p: InvitePreview) -> some View {
        VStack {
            PassNavRow(backLabel: "Close", onBack: model.dismiss)
            Spacer()
            VStack(spacing: 14) {
                EmojiTile(emoji: p.group.emoji, size: 88, radius: 26, fill: PassColor.tile)
                Text("You're already in").outfit(32, .black, tracking: -1.5).foregroundStyle(.white)
                Text("\(p.group.name) is one of your groups.").inter(15).foregroundStyle(PassColor.textSecondary)
            }
            Spacer()
            BottomActions { PassButton(title: "Open group", action: model.openGroup) }
        }
    }
}

private struct InviteScreen: View {
    let preview: InvitePreview
    let onClose: () -> Void
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PassNavRow(backLabel: "Not now", onBack: onClose)
            Spacer()
            VStack(spacing: 0) {
                AvatarView(initials: preview.invitedBy.initials, color: Color(hexString: preview.invitedBy.colorHex), size: 96)
                    .overlay(Circle().strokeBorder(Color(hexString: preview.invitedBy.colorHex), lineWidth: 3).padding(-4))
                    .padding(.bottom, 24).scaleIn()
                Text("\(preview.invitedBy.firstName) passed you\nsomething 👀").outfit(36, .black, tracking: -1.5).foregroundStyle(.white)
                    .multilineTextAlignment(.center).lineSpacing(2).padding(.bottom, 10)
                    .accessibilityAddTraits(.isHeader)
                Text("They want you in on the relay.").inter(15).foregroundStyle(PassColor.textSecondary).padding(.bottom, 28)
                HStack(spacing: 14) {
                    EmojiTile(emoji: "🔒", size: 48, radius: 14)
                    VStack(alignment: .leading, spacing: 3) {
                        Eyebrow(text: "Private group", size: 12, opacity: 0.42)
                        Text(preview.group.name).outfit(19, .heavy, tracking: -0.5).foregroundStyle(.white)
                    }
                    Spacer()
                    AvatarStackView(members: preview.group.membersByJoinOrder.prefix(3).map { ($0.user.initials, Color(hexString: $0.user.colorHex)) }, size: 26)
                }
                .padding(.horizontal, 20).padding(.vertical, 18).passCard()
            }
            .padding(.horizontal, 28)
            .fadeUp()
            Spacer()
            BottomActions {
                PassButton(title: "Open it →", variant: .red, action: onNext).accessibilityIdentifier("invite.openIt")
            }
        }
    }
}

private struct JoinScreen: View {
    @Bindable var model: InviteViewModel
    let preview: InvitePreview

    var body: some View {
        VStack(spacing: 0) {
            PassNavRow(backLabel: "Back", onBack: { withAnimation(PassMotion.screenIn) { model.step = .invite } })
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Eyebrow(text: "You're invited", size: 13, opacity: 0.4).padding(.bottom, 6)
                    Text(preview.group.name).outfit(42, .black, tracking: -2).foregroundStyle(.white).lineSpacing(-2).padding(.bottom, 22)
                        .accessibilityAddTraits(.isHeader)
                    Eyebrow(text: "Members · \(preview.group.memberCount + 1)", size: 12, opacity: 0.35).padding(.bottom, 8)
                    VStack(spacing: 8) {
                        ForEach(preview.group.membersByJoinOrder) { m in
                            memberRow(name: m.user.displayName, initials: m.user.initials, color: Color(hexString: m.user.colorHex),
                                      subtitle: m.role == .creator ? "Created group" : "Member", you: false)
                        }
                        memberRow(name: "You", initials: "ME", color: PassColor.violet, subtitle: "Joining now", you: true)
                    }
                    .padding(.bottom, 18)
                    if let relay = preview.activeRelay {
                        VStack(alignment: .leading, spacing: 4) {
                            Eyebrow(text: "Active relay", size: 11, opacity: 0.4)
                            Text(relay.challengeTitle).outfit(18, .heavy, tracking: -0.5).foregroundStyle(.white)
                            Text("\(relay.submittedCount) of \(relay.participantCount) already went. You'll join from the next Relay.")
                                .inter(13).foregroundStyle(PassColor.text(0.45))
                        }
                        .padding(.horizontal, 16).padding(.vertical, 14).passTintedCard(PassColor.violet, radius: 16)
                    }
                    if let e = model.joinError { InlineMessage(text: e).padding(.top, 12) }
                }
                .padding(.horizontal, 20)
            }
            BottomActions {
                PassButton(title: "Join Group", isLoading: model.isJoining) { Task { await model.join() } }
                    .accessibilityIdentifier("invite.join")
            }
        }
    }

    private func memberRow(name: String, initials: String, color: Color, subtitle: String, you: Bool) -> some View {
        HStack(spacing: 12) {
            AvatarView(initials: initials, color: color, size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).outfit(16, .bold).foregroundStyle(.white)
                Text(subtitle).inter(12).foregroundStyle(PassColor.text(0.38))
            }
            Spacer()
            if you { YouBadge() }
        }
        .padding(.horizontal, 16).padding(.vertical, 13).passCard(radius: 14)
    }
}
