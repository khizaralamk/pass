import SwiftUI

/// Figma "Create a Group": emoji picker + name. Validation inline, button disabled until a name is typed.
struct CreateGroupNameView: View {
    let deps: AppDependencies
    @Environment(AppRouter.self) private var router
    @State private var name = ""
    @State private var emoji = "🌙"
    @State private var error: String?
    @State private var creating = false
    @FocusState private var focused: Bool
    private let emojis = ["🌙", "🏀", "🎮", "🎵", "🍕", "🏖️", "🎯", "⚡", "🌊", "🎉", "🥞", "🐶"]

    var body: some View {
        PassScreen {
            VStack(spacing: 0) {
                PassNavRow(backLabel: "Home", onBack: router.pop)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Create a Group").outfit(36, .black, tracking: -1.5).foregroundStyle(.white).padding(.bottom, 6)
                            .accessibilityAddTraits(.isHeader)
                        Text("Private by default. Only invited members can join.").inter(14).foregroundStyle(PassColor.text(0.4)).padding(.bottom, 26)
                        SectionLabel(label: "Pick an icon")
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                            ForEach(emojis, id: \.self) { e in
                                Button { emoji = e; Haptics.light() } label: {
                                    Text(e).font(.system(size: 22)).frame(maxWidth: .infinity).frame(height: 46)
                                        .background(emoji == e ? PassColor.violet.opacity(0.2) : PassColor.card, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                                            .strokeBorder(emoji == e ? PassColor.violet.opacity(0.6) : PassColor.cardBorder, lineWidth: emoji == e ? 1.5 : 1))
                                }
                                .accessibilityLabel("Icon \(e)")
                                .accessibilityAddTraits(emoji == e ? .isSelected : [])
                            }
                        }
                        .padding(.bottom, 24)
                        SectionLabel(label: "Group name")
                        PassTextField(text: $name, placeholder: "e.g. Friday Night Crew", error: error, limit: Validators.groupNameRange.upperBound)
                            .focused($focused)
                            .submitLabel(.continue)
                            .onSubmit { Task { await create() } }
                            .accessibilityIdentifier("createGroup.name")
                        if let error { InlineMessage(text: error).padding(.top, 8) }
                        if !Validators.normalized(name).isEmpty {
                            HStack(spacing: 12) {
                                EmojiTile(emoji: emoji, size: 40, radius: 12)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(Validators.normalized(name)).outfit(15, .bold).foregroundStyle(.white)
                                    Text("Just you · Private").inter(12).foregroundStyle(PassColor.text(0.35))
                                }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 12).passCard(radius: 14)
                            .padding(.top, 16)
                            .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, 20)
                    .animation(PassMotion.screenIn, value: name.isEmpty)
                }
                .scrollDismissesKeyboard(.interactively)
                BottomActions {
                    PassButton(title: "Continue →", isLoading: creating) { Task { await create() } }
                        .disabled(Validators.normalized(name).isEmpty)
                        .accessibilityIdentifier("createGroup.continue")
                }
            }
        }
        .onAppear { focused = true }
    }

    private func create() async {
        guard !creating else { return }
        switch Validators.groupName(name) {
        case .failure(let e): error = e.message
        case .success(let n):
            error = nil
            creating = true
            defer { creating = false }
            do {
                let group = try await deps.groups.createGroup(name: n, emoji: emoji)
                Haptics.success()
                // Replace the name screen so Back from the invite step returns Home, not to a stale form.
                router.replaceStack(with: [.createGroupInvite(group.id)])
            } catch {
                let e = AppError.wrap(error)
                if !e.isCancellation { self.error = e.userMessage }
            }
        }
    }
}

enum InviteMode { case creating, fromGroup }

/// Figma "Invite Friends": big code, Share Invite Link (native share sheet), Copy Code, privacy note.
/// Used right after creating a group (`.creating`, continues to "Group created!") and from Group Detail.
struct CreateGroupInviteView: View {
    @State var model: GroupDetailViewModel
    let mode: InviteMode
    @Environment(AppRouter.self) private var router
    @State private var share: ShareItems?
    @State private var copied = false

    var body: some View {
        PassScreen {
            VStack(spacing: 0) {
                PassNavRow(backLabel: mode == .creating ? "Home" : "Back", onBack: mode == .creating ? router.popToRoot : router.pop)
                switch model.content {
                case .idle, .loading: LoadingStateView()
                case .failed(let e): ErrorStateView(message: e.userMessage) { Task { await model.load() } }
                case .loaded(let c): content(c.group)
                }
            }
        }
        .task { await model.load() }
        .shareSheet($share)
    }

    private func content(_ group: Group) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Invite Friends").outfit(36, .black, tracking: -1.5).foregroundStyle(.white).padding(.bottom, 6)
                        .accessibilityAddTraits(.isHeader)
                    Text("Share your group code or link.").inter(14).foregroundStyle(PassColor.text(0.4)).padding(.bottom, 24)
                    VStack(spacing: 10) {
                        Eyebrow(text: "Group code", size: 12, opacity: 0.35)
                        Text(group.inviteCode).outfit(38, .black, tracking: 4).foregroundStyle(.white)
                            .accessibilityLabel("Group code \(group.inviteCode.map(String.init).joined(separator: " "))")
                            .accessibilityIdentifier("invite.codeLabel")
                        Text("Share this to invite people to \(group.name)").inter(13).foregroundStyle(PassColor.text(0.3)).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 22).padding(.horizontal, 20).passCard()
                    .padding(.bottom, 12)
                    PassButton(title: "📤 Share Invite Link") { shareInvite(group) }.padding(.bottom, 10)
                        .accessibilityIdentifier("invite.share")
                    PassButton(title: copied ? "✓ Copied" : "🔗 Copy Code", variant: .surface) { copy(group) }.padding(.bottom, 22)
                        .accessibilityIdentifier("invite.copy")
                    HStack(alignment: .top, spacing: 10) {
                        Text("👁️").font(.system(size: 16))
                        Text("PASS groups are private. They never appear publicly or in search.").inter(13).foregroundStyle(PassColor.text(0.5)).lineSpacing(3)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12).passCard(radius: 14)
                    if group.memberCount >= model.rules.maxMembers {
                        InlineMessage(text: "This group is full (\(model.rules.maxMembers) members).", color: PassColor.amber).padding(.top, 12)
                    }
                }
                .padding(.horizontal, 20)
            }
            BottomActions {
                if mode == .creating {
                    PassButton(title: "Done — Create Group") { router.replaceStack(with: [.groupCreated(group.id)]) }
                        .accessibilityIdentifier("invite.done")
                    PassButton(title: "Invite Later", variant: .surface) { router.replaceStack(with: [.groupCreated(group.id)]) }
                        .accessibilityIdentifier("invite.later")
                } else {
                    PassButton(title: "Done", variant: .surface) { router.pop() }
                }
            }
        }
    }

    private func shareInvite(_ group: Group) {
        guard let link = model.inviteLink else { return }
        let text = "Join \(group.name) on PASS 🔥 Use code \(group.inviteCode) or open \(link.absoluteString)"
        share = ShareItems(items: [text])
    }

    private func copy(_ group: Group) {
        UIPasteboard.general.string = group.inviteCode
        Haptics.light()
        withAnimation { copied = true }
        Task { try? await Task.sleep(for: .seconds(2)); withAnimation { copied = false } }
    }
}

/// Figma "Group created!" with the 3-member rule enforced on the Start a Relay button.
struct GroupCreatedView: View {
    @State var model: GroupDetailViewModel
    @Environment(AppRouter.self) private var router
    @Environment(AppSession.self) private var session

    var body: some View {
        PassScreen {
            VStack(spacing: 0) {
                Spacer()
                if let g = model.group {
                    VStack(spacing: 0) {
                        Text(g.emoji).font(.system(size: 44))
                            .frame(width: 88, height: 88)
                            .background(PassColor.tile, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(PassColor.text(0.08), lineWidth: 1))
                            .padding(.bottom, 22)
                            .scaleIn()
                        Text("Group created!").outfit(44, .black, tracking: -2.5).foregroundStyle(.white).padding(.bottom, 10)
                            .accessibilityAddTraits(.isHeader)
                        (Text(g.name).foregroundColor(.white).fontWeight(.semibold) + Text("\nis ready. Invite friends to start a relay.").foregroundColor(PassColor.text(0.5)))
                            .font(PassFont.inter(15)).multilineTextAlignment(.center).lineSpacing(5)
                        HStack(spacing: 8) {
                            UserAvatarView(name: session.user?.displayName ?? "You", colorHex: session.user?.colorHex ?? "#6B46FF", avatarFileName: session.user?.avatarFileName, size: 40)
                            Button { router.replaceStack(with: [.groupDetail(g.id), .createGroupInvite(g.id)]) } label: {
                                Text("+ invite friends →").inter(13).foregroundStyle(PassColor.text(0.3))
                                    .padding(.horizontal, 14).padding(.vertical, 6)
                                    .background(PassColor.card, in: Capsule())
                                    .overlay(Capsule().strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3])).foregroundStyle(PassColor.text(0.15)))
                            }
                        }
                        .padding(.top, 20)
                    }
                    .padding(.horizontal, 28)
                    .fadeUp()
                } else if case .failed(let e) = model.content {
                    ErrorStateView(message: e.userMessage) { Task { await model.load() } }
                } else {
                    LoadingStateView()
                }
                Spacer()
                BottomActions {
                    if !model.canStartRelay {
                        Text("Invite at least \(model.friendsNeeded) friend\(model.friendsNeeded == 1 ? "" : "s") to start a Relay.")
                            .inter(13).foregroundStyle(PassColor.text(0.35))
                    }
                    PassButton(title: "Start a Relay 🔥", variant: .red) {
                        router.replaceStack(with: [.groupDetail(model.groupID), .newRelayChallenge(model.groupID)])
                    }
                    .disabled(!model.canStartRelay)
                    .accessibilityIdentifier("created.startRelay")
                    PassButton(title: "Go to Group", variant: .surface) { router.replaceStack(with: [.groupDetail(model.groupID)]) }
                        .accessibilityIdentifier("created.goToGroup")
                }
            }
        }
        .task { await model.load() }
        .task { await model.observeChanges() }
        .navigationBarBackButtonHidden(true)
    }
}
