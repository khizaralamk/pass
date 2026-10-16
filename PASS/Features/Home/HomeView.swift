import SwiftUI

/// Figma S4 (three states). Header: "PASS" + avatar. Body: active relays, "+ New Relay", groups, "+ New Group".
struct HomeView: View {
    @Environment(\.dependencies) private var deps
    @Environment(AppRouter.self) private var router
    @Environment(AppSession.self) private var session
    @State private var model: HomeViewModel?

    var body: some View {
        PassScreen {
            if let model {
                HomeContent(model: model)
            } else {
                Color.clear.onAppear { if let deps { model = HomeViewModel(deps: deps) } }
            }
        }
    }
}

private struct HomeContent: View {
    let model: HomeViewModel
    @Environment(AppRouter.self) private var router
    @Environment(AppSession.self) private var session

    var body: some View {
        VStack(spacing: 0) {
            header
            switch model.content {
            case .idle, .loading:
                LoadingStateView()
            case .failed(let error):
                ErrorStateView(message: error.userMessage) { Task { await model.load() } }
            case .loaded(let content):
                list(content)
            }
        }
        .task { await model.load() }
        .task { await model.observeChanges() }
    }

    private var header: some View {
        HStack {
            Text("PASS").outfit(26, .black, tracking: -1).foregroundStyle(.white).accessibilityAddTraits(.isHeader)
            Spacer()
            Button { router.push(.profile) } label: {
                UserAvatarView(name: session.user?.displayName ?? "You", colorHex: session.user?.colorHex ?? "#6B46FF",
                               avatarFileName: session.user?.avatarFileName, size: 36)
            }
            .accessibilityLabel("Profile")
            .accessibilityIdentifier("home.profile")
        }
        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 12)
    }

    private func list(_ content: HomeViewModel.Content) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if content.relays.isEmpty {
                    emptyState
                } else {
                    SectionLabel(label: "Active Relays")
                    ForEach(Array(content.relays.enumerated()), id: \.element.id) { index, relay in
                        relayCard(relay).padding(.bottom, 12).fadeUp(index)
                    }
                    dashedRow("New Relay", color: PassColor.violet, textOpacity: 0.4) { router.push(.newRelayGroup(preselected: nil)) }
                        .accessibilityIdentifier("home.newRelay")
                        .padding(.bottom, 20)
                }
                SectionLabel(label: "Your Groups")
                ForEach(content.groups) { group in
                    GroupRow(group: group, relay: content.activeRelay(for: group)) { router.push(.groupDetail(group.id)) }
                        .padding(.bottom, 8)
                }
                dashedRow("New Group", color: .white, fill: 0.02, border: 0.1, textOpacity: 0.3) { router.push(.createGroupName) }
                    .accessibilityIdentifier("home.newGroup")
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 20)
        }
        .refreshable { await model.load(showLoading: false) }
        .accessibilityIdentifier("home.list")
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            Text("P").outfit(34, .black).foregroundStyle(PassColor.text(0.25))
                .frame(width: 72, height: 72)
                .background(PassColor.violet.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(PassColor.text(0.06), lineWidth: 1))
                .padding(.bottom, 16)
            Text("Nothing active right now.").outfit(22, .heavy, tracking: -0.8).foregroundStyle(PassColor.text(0.55))
                .padding(.bottom, 6)
            Text("Start a relay to kick things off.").inter(14).foregroundStyle(PassColor.text(0.28))
                .padding(.bottom, 22)
            PassButton(title: "Start a Relay", fullWidth: false) { router.push(.newRelayGroup(preselected: nil)) }
                .accessibilityIdentifier("home.startRelay")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.empty")
    }

    @ViewBuilder
    private func relayCard(_ relay: Relay) -> some View {
        if let me = model.me, relay.isHolder(me) {
            YourTurnCard(relay: relay, me: me) { router.push(relay.hasSubmitted(me) ? .passBaton(relay.id) : .baton(relay.id)) }
        } else {
            WaitingCard(relay: relay) { router.push(.progress(relay.id)) }
        }
    }

    private func dashedRow(_ title: String, color: Color, fill: Double = 0.06, border: Double = 0.25, textOpacity: Double, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text("+").font(.system(size: 16)).foregroundStyle(color == .white ? PassColor.text(0.35) : color)
                    .frame(width: 26, height: 26)
                    .background(color.opacity(color == .white ? 0.05 : 0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(title).inter(14, .medium).foregroundStyle(PassColor.text(textOpacity))
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .passDashedCard(color, fill: fill, border: border)
        }
        .buttonStyle(PressableRowStyle())
    }
}

// MARK: - Cards

/// Figma state A: violet gradient card, "YOUR TURN", challenge, avatars, countdown, segment bar, "Take your turn 🔥".
struct YourTurnCard: View {
    let relay: Relay
    let me: UserID
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                StatusDotLabel(text: relay.currentTurn?.isRescue == true ? "Last chance" : "Your turn")
                Spacer()
                Text("\(relay.groupEmoji) \(relay.groupName)").inter(12).foregroundStyle(PassColor.text(0.35))
            }
            .padding(.horizontal, 20).padding(.top, 14)
            Text(relay.challengeTitle).outfit(34, .black, tracking: -1.6).foregroundStyle(.white).lineSpacing(-3)
                .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 6)
            HStack {
                AvatarStackView(members: relay.participants.map { ($0.user.initials, Color(hexString: $0.user.colorHex)) }, size: 22)
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: "clock").font(.system(size: 11, weight: .bold)).foregroundStyle(PassColor.text(0.4))
                    if let deadline = relay.currentTurn?.deadline { CountdownText(deadline: deadline) }
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 10)
            VStack(alignment: .leading, spacing: 4) {
                MemberSegmentBar(segments: relay.participants.map { p in
                    .init(id: p.id.raw, color: p.hasSubmitted ? Color(hexString: p.user.colorHex) : p.id == me ? PassColor.violet.opacity(0.5) : PassColor.text(0.1))
                })
                Text("\(relay.submittedCount)/\(relay.participantCount) submitted").inter(11).foregroundStyle(PassColor.text(0.28))
            }
            .padding(.horizontal, 20).padding(.bottom, 10)
            PassButton(title: relay.hasSubmitted(me) ? "Pass the Baton 🔥" : "Take your turn 🔥", height: 50, fontSize: 15, action: action)
                .padding(.horizontal, 14).padding(.bottom, 14)
                .accessibilityIdentifier("home.takeTurn")
        }
        .background(LinearGradient(colors: [Color(hex: 0x200D52), Color(hex: 0x0E0E0E)], startPoint: .topLeading, endPoint: .bottom),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(PassColor.violet.opacity(0.3), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Your turn. \(relay.challengeTitle), \(relay.groupName). \(relay.submittedCount) of \(relay.participantCount) submitted.")
    }
}

/// Figma state B: red-tinted card, "LIVE", "BATON WITH NAME 🔥", challenge, segment bar, "View Relay Progress".
struct WaitingCard: View {
    let relay: Relay
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                StatusDotLabel(text: "Live")
                Spacer()
                Text("\(relay.groupEmoji) \(relay.groupName)").inter(12).foregroundStyle(PassColor.text(0.35))
            }
            .padding(.horizontal, 20).padding(.top, 14)
            Text("BATON WITH \(relay.holder?.user.firstName.uppercased() ?? "…") 🔥").outfit(24, .black, tracking: -1).foregroundStyle(.white)
                .padding(.horizontal, 20).padding(.top, 10)
            Text(relay.challengeTitle).inter(13).foregroundStyle(PassColor.text(0.4))
                .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 6)
            VStack(alignment: .leading, spacing: 4) {
                MemberSegmentBar(segments: relay.participants.map { p in
                    .init(id: p.id.raw, color: p.hasSubmitted ? Color(hexString: p.user.colorHex) : PassColor.text(0.1))
                })
                Text("\(relay.submittedCount)/\(relay.participantCount) submitted").inter(11).foregroundStyle(PassColor.text(0.28))
            }
            .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 10)
            PassButton(title: "View Relay Progress", variant: .surface, height: 46, fontSize: 14, action: action)
                .padding(.horizontal, 14).padding(.bottom, 14)
                .accessibilityIdentifier("home.viewProgress")
        }
        .background(LinearGradient(colors: [Color(hex: 0x1A0A0E), Color(hex: 0x0E0E0E)], startPoint: .topLeading, endPoint: .bottom),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(PassColor.red.opacity(0.18), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Live. Baton with \(relay.holder?.user.firstName ?? "someone"). \(relay.challengeTitle), \(relay.groupName).")
    }
}

/// Group row: emoji tile, name, "Relay · 2/5 submitted · 5 members" or "No active relay", streak, live dot, chevron.
struct GroupRow: View {
    let group: Group
    let relay: Relay?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                EmojiTile(emoji: group.emoji)
                VStack(alignment: .leading, spacing: 1) {
                    Text(group.name).outfit(14, .bold).foregroundStyle(.white).lineLimit(1)
                    Text(subtitle).inter(12).foregroundStyle(PassColor.text(0.35)).lineLimit(1)
                }
                Spacer(minLength: 8)
                if group.stats.currentStreak > 0 {
                    Text("🔥 \(group.stats.currentStreak)").inter(12, .semibold).foregroundStyle(PassColor.amber)
                }
                if relay != nil { Circle().fill(PassColor.red).frame(width: 6, height: 6) }
                ChevronRight()
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .passCard(radius: 14)
        }
        .buttonStyle(PressableRowStyle())
        .accessibilityLabel("\(group.name). \(subtitle). Streak \(group.stats.currentStreak).")
        .accessibilityIdentifier("home.group.\(group.id.raw)")
    }

    private var subtitle: String {
        let members = "\(group.memberCount) member\(group.memberCount == 1 ? "" : "s")"
        if let relay { return "Relay · \(relay.submittedCount)/\(relay.participantCount) submitted · \(members)" }
        return "No active relay · \(members)"
    }
}
