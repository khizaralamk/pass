import SwiftUI

/// Figma "Start a Relay · Which group?": groups with an active relay redirect, groups under 3 are disabled with the reason.
struct NewRelayGroupView: View {
    @State var model: NewRelayViewModel
    @Environment(AppRouter.self) private var router

    var body: some View {
        PassScreen {
            VStack(spacing: 0) {
                PassNavRow(backLabel: "Home", onBack: router.pop)
                switch model.groups {
                case .idle, .loading: LoadingStateView()
                case .failed(let e): ErrorStateView(message: e.userMessage) { Task { await model.loadGroups() } }
                case .loaded(let options): list(options)
                }
            }
        }
        .task { await model.loadGroups() }
    }

    private func list(_ options: [NewRelayViewModel.GroupOption]) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Start a Relay").outfit(36, .black, tracking: -1.5).foregroundStyle(.white).accessibilityAddTraits(.isHeader)
                    Text("Which group?").inter(14).foregroundStyle(PassColor.text(0.45)).padding(.top, 6).padding(.bottom, 20)
                    if options.isEmpty {
                        VStack(spacing: 10) {
                            Text("No groups yet").outfit(18, .heavy).foregroundStyle(PassColor.text(0.5))
                            Text("Create a group and invite 2 friends to start a Relay.").inter(13).foregroundStyle(PassColor.text(0.3)).multilineTextAlignment(.center)
                            PassButton(title: "+ New Group", variant: .surface, height: 46, fontSize: 14, fullWidth: false) { router.replaceStack(with: [.createGroupName]) }
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 30)
                    }
                    VStack(spacing: 10) {
                        ForEach(options) { option in
                            groupRow(option)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            BottomActions {
                PassButton(title: "Continue →", action: model.continueToChallenge).disabled(model.selectedGroupID == nil)
                    .accessibilityIdentifier("newRelay.continue")
            }
        }
    }

    private func groupRow(_ option: NewRelayViewModel.GroupOption) -> some View {
        let hasRelay = option.activeRelay != nil
        let tooSmall = !hasRelay && option.group.memberCount < model.rules.minMembersToStart
        let selected = model.selectedGroupID == option.id && model.isSelectable(option)
        let disabled = hasRelay || tooSmall
        return Button { model.tap(option) } label: {
            HStack(spacing: 14) {
                EmojiTile(emoji: option.group.emoji, size: 50, radius: 15)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.group.name).outfit(17, .bold, tracking: -0.3).foregroundStyle(.white)
                    Text(hasRelay ? "Active relay in progress · tap to view"
                         : tooSmall ? "\(option.group.memberCount) member\(option.group.memberCount == 1 ? "" : "s") · need at least \(model.rules.minMembersToStart)"
                         : "\(option.group.memberCount) members")
                        .inter(13).foregroundStyle(hasRelay ? PassColor.amber : tooSmall ? Color(red: 1, green: 0.39, blue: 0.39).opacity(0.7) : PassColor.text(0.4))
                }
                Spacer()
                if hasRelay {
                    ChevronRight()
                } else if !tooSmall {
                    ZStack {
                        Circle().fill(selected ? PassColor.violet : PassColor.text(0.08))
                        if !selected { Circle().strokeBorder(PassColor.text(0.18), lineWidth: 1.5) }
                        if selected { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white) }
                    }
                    .frame(width: 22, height: 22)
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 16)
            .opacity(disabled ? 0.5 : 1)
            .passCard(radius: 18, fill: selected ? PassColor.violet.opacity(0.12) : disabled ? PassColor.text(0.03) : PassColor.card,
                      border: selected ? PassColor.violet.opacity(0.45) : disabled ? PassColor.text(0.06) : PassColor.cardBorder)
        }
        .buttonStyle(PressableRowStyle())
        .disabled(tooSmall)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("newRelay.group.\(option.id.raw)")
    }
}

/// Figma "Choose a Challenge": presets + "Write your own".
struct NewRelayChallengeView: View {
    @State var model: NewRelayViewModel
    @Environment(AppRouter.self) private var router
    @FocusState private var customFocused: Bool

    var body: some View {
        PassScreen {
            VStack(spacing: 0) {
                PassNavRow(backLabel: "Back", onBack: router.pop)
                switch model.challenges {
                case .idle, .loading: LoadingStateView()
                case .failed(let e): ErrorStateView(message: e.userMessage) { Task { await model.loadChallenges() } }
                case .loaded(let list): content(list)
                }
            }
        }
        .task { await model.loadChallenges() }
        .onChange(of: customFocused) { _, f in if f { model.isWritingOwn = true; model.selectedChallenge = nil } }
    }

    private func content(_ list: [Challenge]) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Choose a\nChallenge").outfit(36, .black, tracking: -1.5).foregroundStyle(.white).lineSpacing(-2).padding(.bottom, 18)
                        .accessibilityAddTraits(.isHeader)
                    VStack(spacing: 8) {
                        ForEach(list) { c in
                            let sel = model.selectedChallenge == c.title && !model.isWritingOwn
                            Button { model.selectPreset(c.title); customFocused = false; Haptics.light() } label: {
                                HStack(spacing: 14) {
                                    Text(c.title).outfit(16, .bold, tracking: -0.3).foregroundStyle(.white).multilineTextAlignment(.leading)
                                    Spacer()
                                    if sel {
                                        Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                                            .frame(width: 22, height: 22).background(PassColor.violet, in: Circle())
                                    }
                                }
                                .padding(.horizontal, 16).padding(.vertical, 14)
                                .passCard(radius: 16, fill: sel ? PassColor.violet.opacity(0.12) : PassColor.card, border: sel ? PassColor.violet.opacity(0.45) : PassColor.cardBorder)
                            }
                            .buttonStyle(PressableRowStyle())
                            .accessibilityAddTraits(sel ? .isSelected : [])
                        }
                    }
                    .padding(.bottom, 10)
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow(text: "Write your own", size: 12, opacity: 0.4)
                        TextField("", text: $model.customChallenge, prompt: Text("e.g. Send your most recent photo").foregroundStyle(PassColor.text(0.25)))
                            .font(PassFont.outfit(16, .bold)).foregroundStyle(.white).tint(PassColor.violet)
                            .focused($customFocused)
                            .submitLabel(.done)
                            .onSubmit(model.continueToReview)
                            .onChange(of: model.customChallenge) { _, v in
                                if v.count > Validators.challengeRange.upperBound { model.customChallenge = String(v.prefix(Validators.challengeRange.upperBound)) }
                                if !v.isEmpty { model.isWritingOwn = true; model.selectedChallenge = nil }
                            }
                            .accessibilityIdentifier("newRelay.custom")
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .passCard(radius: 16, fill: model.isWritingOwn ? PassColor.violet.opacity(0.1) : PassColor.card, border: model.isWritingOwn ? PassColor.violet.opacity(0.4) : PassColor.cardBorder)
                    if let e = model.challengeError { InlineMessage(text: e).padding(.top, 8) }
                }
                .padding(.horizontal, 20)
            }
            .scrollDismissesKeyboard(.interactively)
            BottomActions {
                PassButton(title: "Use This →", action: model.continueToReview).disabled(model.activeChallenge == nil)
                    .accessibilityIdentifier("newRelay.useThis")
            }
        }
    }
}

/// Figma "New Relay · Start": review with the Baton order, "you first" badge, hidden note, "Start Relay — you go first 🔥".
struct NewRelayReviewView: View {
    @State var model: NewRelayViewModel
    @Environment(AppRouter.self) private var router
    @Environment(AppSession.self) private var session

    var body: some View {
        PassScreen {
            VStack(spacing: 0) {
                PassNavRow(backLabel: "Back", onBack: router.pop)
                if let group = model.selectedGroup, let challenge = model.selectedChallenge {
                    content(group, challenge)
                } else if case .failed(let e) = model.groups {
                    ErrorStateView(message: e.userMessage) { Task { await model.loadGroups() } }
                } else {
                    LoadingStateView()
                }
            }
        }
        .task { await model.loadGroupIfNeeded() }
    }

    private func content(_ group: Group, _ challenge: String) -> some View {
        let me = session.user?.id
        let ordered = group.membersByJoinOrder.sorted { a, b in (a.id == me ? 0 : 1) < (b.id == me ? 0 : 1) }
        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Eyebrow(text: "New relay · \(group.name)", size: 12, opacity: 0.38).padding(.bottom, 8)
                    Text(challenge).outfit(48, .black, tracking: -2.5).foregroundStyle(.white).lineSpacing(-4).padding(.bottom, 22)
                        .accessibilityAddTraits(.isHeader)
                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow(text: "Baton order · \(group.memberCount) members", size: 12, opacity: 0.38)
                        ForEach(Array(ordered.enumerated()), id: \.element.id) { i, m in
                            HStack(spacing: 10) {
                                Text("\(i + 1)").outfit(11, .bold).foregroundStyle(PassColor.text(0.5))
                                    .frame(width: 22, height: 22).background(PassColor.text(0.08), in: Circle())
                                AvatarView(initials: m.user.initials, color: Color(hexString: m.user.colorHex), size: 32)
                                Text(m.id == me ? "You" : m.user.displayName).outfit(15, .bold).foregroundStyle(.white)
                                Spacer()
                                if i == 0 {
                                    Text("you first").inter(12, .semibold).foregroundStyle(PassColor.red)
                                        .padding(.horizontal, 10).padding(.vertical, 2).background(PassColor.red.opacity(0.12), in: Capsule())
                                }
                            }
                        }
                        Text("After you, each person picks who goes next.").inter(11).foregroundStyle(PassColor.text(0.3)).padding(.top, 2)
                    }
                    .padding(.horizontal, 18).padding(.vertical, 16).passCard().padding(.bottom, 14)
                    HStack(spacing: 8) {
                        Text("👁️").font(.system(size: 16))
                        Text("Submissions stay hidden until all \(group.memberCount) submit.").inter(13).foregroundStyle(PassColor.text(0.55))
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12).passCard(radius: 14)
                    if let e = model.startError { InlineMessage(text: e).padding(.top, 12) }
                }
                .padding(.horizontal, 20)
            }
            BottomActions {
                PassButton(title: "Start Relay — you go first 🔥", variant: .red, isLoading: model.isStarting) { Task { await model.start() } }
                    .accessibilityIdentifier("newRelay.start")
            }
        }
    }
}
