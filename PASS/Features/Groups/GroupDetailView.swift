import SwiftUI

/// Figma Group Detail + the spec additions: stats card (streak prominent), invite row, history, members with actions,
/// leave group. Start Relay is disabled under 3 members with the spec's copy.
struct GroupDetailView: View {
    @State var model: GroupDetailViewModel
    @Environment(AppRouter.self) private var router
    @State private var showLeaveConfirm = false
    @State private var share: ShareItems?

    var body: some View {
        PassScreen {
            VStack(spacing: 0) {
                PassNavRow(backLabel: "Home", onBack: router.pop)
                switch model.content {
                case .idle, .loading: LoadingStateView()
                case .failed(let e): ErrorStateView(message: e.userMessage) { Task { await model.load() } }
                case .loaded(let c): content(c)
                }
            }
        }
        .task { await model.load() }
        .task { await model.observeChanges() }
        .confirmationDialog("Leave \(model.group?.name ?? "group")?", isPresented: $showLeaveConfirm, titleVisibility: .visible) {
            Button("Leave Group", role: .destructive) { Task { await model.leaveGroup() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(model.content.value?.activeRelay != nil
                 ? "Leaving now ends the active Relay for everyone and resets the streak."
                 : "You'll need a new invite to come back.")
        }
        .shareSheet($share)
        .alert("Couldn't do that", isPresented: Binding(get: { model.actionError != nil }, set: { if !$0 { model.actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.actionError?.userMessage ?? "") }
    }

    private func content(_ c: GroupDetailViewModel.Content) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 12) {
                        EmojiTile(emoji: c.group.emoji, size: 48, radius: 14)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.group.name).outfit(30, .black, tracking: -1.3).foregroundStyle(.white).lineLimit(2)
                                .accessibilityAddTraits(.isHeader)
                            Text("Private · \(c.group.memberCount) member\(c.group.memberCount == 1 ? "" : "s")").inter(14).foregroundStyle(PassColor.text(0.4))
                        }
                    }
                    .padding(.bottom, 16)

                    statsCard(c.group).padding(.bottom, 12)

                    if let relay = c.activeRelay {
                        activeRelayCard(relay).padding(.bottom, 18)
                    } else {
                        VStack(spacing: 4) {
                            Text("No active relay").outfit(15, .bold).foregroundStyle(PassColor.text(0.4))
                            Text("Start one below").inter(13).foregroundStyle(PassColor.text(0.28))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .passCard(radius: 16).padding(.bottom, 18)
                    }

                    inviteRow(c.group).padding(.bottom, 18)

                    SectionLabel(label: "Members", action: "Manage") { router.push(.groupMembers(model.groupID)) }
                    VStack(spacing: 8) {
                        ForEach(c.group.membersByJoinOrder) { m in
                            memberRow(m)
                        }
                    }
                    .padding(.bottom, 20)

                    Button { router.push(.groupHistory(model.groupID)) } label: {
                        HStack(spacing: 12) {
                            EmojiTile(emoji: "🎞️", size: 38)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Past Relays").outfit(15, .bold).foregroundStyle(.white)
                                Text("\(c.group.stats.completedRelays) completed · watch any Reveal again").inter(12).foregroundStyle(PassColor.text(0.35))
                            }
                            Spacer()
                            ChevronRight()
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12).passCard(radius: 14)
                    }
                    .buttonStyle(PressableRowStyle())
                    .accessibilityIdentifier("group.history")
                    .padding(.bottom, 10)

                    Button { showLeaveConfirm = true } label: {
                        Text("Leave Group").inter(14, .semibold).foregroundStyle(PassColor.red)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                    }
                    .accessibilityIdentifier("group.leave")

                    if model.demoAvailable { demoControls(c) }
                }
                .padding(.horizontal, 20)
            }
            .refreshable { await model.load(showLoading: false) }

            BottomActions {
                if c.activeRelay != nil {
                    Text("One relay at a time per group").inter(14).foregroundStyle(PassColor.text(0.35))
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(PassColor.card, in: Capsule())
                        .overlay(Capsule().strokeBorder(PassColor.text(0.08), lineWidth: 1))
                } else {
                    if !model.canStartRelay {
                        Text("Invite at least \(model.friendsNeeded) friend\(model.friendsNeeded == 1 ? "" : "s") to start a Relay.")
                            .inter(13).foregroundStyle(PassColor.text(0.35)).multilineTextAlignment(.center)
                    }
                    PassButton(title: "+ Start New Relay", action: model.startRelayTapped)
                        .disabled(!model.canStartRelay)
                        .accessibilityIdentifier("group.startRelay")
                }
            }
        }
    }

    /// Spec §7: streak visually more prominent than the lifetime count.
    private func statsCard(_ group: Group) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("🔥 \(group.stats.currentStreak)").outfit(34, .black, tracking: -1.5).foregroundStyle(.white)
                Text("Relay streak").inter(12).foregroundStyle(PassColor.text(0.45))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(group.stats.completedRelays)").outfit(20, .heavy).foregroundStyle(PassColor.text(0.7))
                Text("Relays completed").inter(12).foregroundStyle(PassColor.text(0.35))
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .background(LinearGradient(colors: [PassColor.amber.opacity(0.14), PassColor.card], startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(PassColor.amber.opacity(0.25), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Relay streak \(group.stats.currentStreak). \(group.stats.completedRelays) relays completed.")
    }

    private func activeRelayCard(_ relay: Relay) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: "Active relay", size: 11, opacity: 0.4).padding(.bottom, 4)
            Text(relay.challengeTitle).outfit(22, .heavy, tracking: -0.8).foregroundStyle(.white).padding(.bottom, 10)
            HStack(spacing: 5) {
                ForEach(relay.orderedForProgress) { p in
                    VStack(spacing: 4) {
                        Capsule().fill(segmentColor(p, relay)).frame(height: 3)
                        Text(p.user.firstName).inter(9).foregroundStyle(nameColor(p, relay)).lineLimit(1)
                    }
                }
            }
            .padding(.bottom, 8)
            Text("\(relay.submittedCount)/\(relay.participantCount) submitted · \(relay.holder?.user.firstName ?? "…") has the baton")
                .inter(13).foregroundStyle(PassColor.text(0.45)).padding(.bottom, 10)
            PassButton(title: "View Progress", variant: .surface, height: 46, fontSize: 14, action: model.viewProgress)
                .accessibilityIdentifier("group.viewProgress")
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .passTintedCard(PassColor.violet)
    }

    private func segmentColor(_ p: RelayParticipant, _ r: Relay) -> Color {
        if p.hasSubmitted { return Color(hexString: p.user.colorHex) }
        if p.state == .holding { return Color(hexString: p.user.colorHex).opacity(0.4) }
        return PassColor.text(0.1)
    }

    private func nameColor(_ p: RelayParticipant, _ r: Relay) -> Color {
        if p.hasSubmitted { return Color(hexString: p.user.colorHex) }
        if p.state == .holding { return PassColor.text(0.7) }
        return PassColor.text(0.3)
    }

    private func inviteRow(_ group: Group) -> some View {
        Button { router.push(.createGroupInvite(group.id)) } label: {
            HStack(spacing: 12) {
                EmojiTile(emoji: "🔗", size: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Invite friends").outfit(15, .bold).foregroundStyle(.white)
                    Text("Code \(group.inviteCode) · up to \(model.rules.maxMembers) members").inter(12).foregroundStyle(PassColor.text(0.35))
                }
                Spacer()
                ChevronRight()
            }
            .padding(.horizontal, 14).padding(.vertical, 12).passCard(radius: 14)
        }
        .buttonStyle(PressableRowStyle())
        .accessibilityIdentifier("group.invite")
    }

    private func memberRow(_ m: GroupMember) -> some View {
        HStack(spacing: 12) {
            AvatarView(initials: m.user.initials, color: Color(hexString: m.user.colorHex), size: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text(m.user.displayName).outfit(15, .bold).foregroundStyle(.white)
                Text(m.role == .creator ? "Admin" : "Member").inter(12).foregroundStyle(PassColor.text(0.35))
            }
            Spacer()
            if m.id == model.me { YouBadge() }
        }
        .padding(.horizontal, 16).padding(.vertical, 12).passCard(radius: 14)
        .accessibilityElement(children: .combine)
    }

    private func demoControls(_ c: GroupDetailViewModel.Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(label: "Demo controls (mock backend)")
            HStack(spacing: 8) {
                PassButton(title: "+ Friend joins", variant: .outline, height: 40, fontSize: 13) { Task { await model.demoSimulateJoin() } }
                PassButton(title: "A member leaves", variant: .outline, height: 40, fontSize: 13) { Task { await model.demoMemberLeaves() } }
            }
            Text("These buttons stand in for other people's phones. They disappear in release builds.")
                .inter(11).foregroundStyle(PassColor.text(0.25))
        }
        .padding(.top, 10).padding(.bottom, 30)
    }
}
