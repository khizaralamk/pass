import SwiftUI

/// Spec §26 member management: creator can remove; anyone can report or block another member.
struct GroupMembersView: View {
    @State var model: GroupDetailViewModel
    @Environment(AppRouter.self) private var router
    @State private var pendingRemove: GroupMember?
    @State private var pendingBlock: GroupMember?
    @State private var reportTarget: GroupMember?

    var body: some View {
        PassScreen {
            VStack(spacing: 0) {
                PassNavRow(backLabel: "Back", onBack: router.pop)
                switch model.content {
                case .idle, .loading: LoadingStateView()
                case .failed(let e): ErrorStateView(message: e.userMessage) { Task { await model.load() } }
                case .loaded(let c): list(c.group)
                }
            }
        }
        .task { await model.load() }
        .task { await model.observeChanges() }
        .confirmationDialog("Remove \(pendingRemove?.user.displayName ?? "")?", isPresented: Binding(get: { pendingRemove != nil }, set: { if !$0 { pendingRemove = nil } }), titleVisibility: .visible) {
            Button("Remove from group", role: .destructive) {
                if let m = pendingRemove { Task { await model.removeMember(m.id) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(model.content.value?.activeRelay != nil
                 ? "This ends the active Relay for everyone and resets the streak."
                 : "They'll need a new invite to come back.")
        }
        .confirmationDialog("Block \(pendingBlock?.user.displayName ?? "")?", isPresented: Binding(get: { pendingBlock != nil }, set: { if !$0 { pendingBlock = nil } }), titleVisibility: .visible) {
            Button("Block", role: .destructive) {
                if let m = pendingBlock { Task { await model.block(m.user) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They won't be able to invite you to new groups. You can unblock them in Privacy settings.")
        }
        .sheet(item: $reportTarget) { m in
            ReportSheet(title: "Report \(m.user.displayName)", target: .user(m.id)) { reason, details in
                await model.report(.user(m.id), reason: reason, details: details)
            }
        }
        .alert("Couldn't do that", isPresented: Binding(get: { model.actionError != nil }, set: { if !$0 { model.actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.actionError?.userMessage ?? "") }
    }

    private func list(_ group: Group) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Members").outfit(36, .black, tracking: -1.5).foregroundStyle(.white).padding(.bottom, 6)
                    .accessibilityAddTraits(.isHeader)
                Text("\(group.memberCount) of \(model.rules.maxMembers) · \(group.name)").inter(14).foregroundStyle(PassColor.text(0.4)).padding(.bottom, 22)
                VStack(spacing: 8) {
                    ForEach(group.membersByJoinOrder) { m in
                        HStack(spacing: 12) {
                            AvatarView(initials: m.user.initials, color: Color(hexString: m.user.colorHex), size: 40)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(m.user.displayName).outfit(16, .bold).foregroundStyle(.white)
                                Text(m.role == .creator ? "Admin" : "Member").inter(12).foregroundStyle(PassColor.text(0.35))
                            }
                            Spacer()
                            if m.id == model.me {
                                YouBadge()
                            } else {
                                Menu {
                                    Button { reportTarget = m } label: { Label("Report", systemImage: "flag") }
                                    Button(role: .destructive) { pendingBlock = m } label: { Label("Block", systemImage: "hand.raised") }
                                    if model.isCreator {
                                        Button(role: .destructive) { pendingRemove = m } label: { Label("Remove from group", systemImage: "person.badge.minus") }
                                    }
                                } label: {
                                    Image(systemName: "ellipsis").font(.system(size: 16, weight: .bold)).foregroundStyle(PassColor.text(0.5))
                                        .frame(width: 36, height: 36).background(PassColor.text(0.06), in: Circle())
                                }
                                .accessibilityLabel("Actions for \(m.user.displayName)")
                                .accessibilityIdentifier("members.actions.\(m.id.raw)")
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12).passCard(radius: 14)
                    }
                }
                if !model.isCreator {
                    Text("Only the admin can remove members.").inter(12).foregroundStyle(PassColor.text(0.25)).padding(.top, 12)
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

/// Shared report form (spec §26) for a member or a Reveal.
struct ReportSheet: View {
    let title: String
    let target: ReportTarget
    let submit: (ReportReason, String) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var reason: ReportReason = .harassment
    @State private var details = ""
    @State private var error: String?
    @State private var sending = false

    var body: some View {
        NavigationStack {
            PassScreen {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title).outfit(28, .black, tracking: -1).foregroundStyle(.white).padding(.bottom, 4)
                        Text("Reports are private. The PASS team reviews them within 24 hours.").inter(13).foregroundStyle(PassColor.text(0.4)).padding(.bottom, 20)
                        SectionLabel(label: "Reason")
                        VStack(spacing: 8) {
                            ForEach(ReportReason.allCases) { r in
                                Button { reason = r } label: {
                                    HStack {
                                        Text(r.rawValue).inter(15, .medium).foregroundStyle(.white)
                                        Spacer()
                                        Image(systemName: reason == r ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(reason == r ? PassColor.violet : PassColor.text(0.2))
                                    }
                                    .padding(.horizontal, 16).padding(.vertical, 13)
                                    .passCard(radius: 14, fill: reason == r ? PassColor.violet.opacity(0.12) : PassColor.card,
                                              border: reason == r ? PassColor.violet.opacity(0.45) : PassColor.cardBorder)
                                }
                            }
                        }
                        .padding(.bottom, 18)
                        SectionLabel(label: "Details (optional)")
                        TextField("", text: $details, prompt: Text("What happened?").foregroundStyle(PassColor.text(0.25)), axis: .vertical)
                            .lineLimit(3...6)
                            .font(PassFont.inter(15)).foregroundStyle(.white).tint(PassColor.violet)
                            .padding(14).passCard(radius: 14)
                            .onChange(of: details) { _, v in if v.count > Validators.reportDetailsMax { details = String(v.prefix(Validators.reportDetailsMax)) } }
                        if let error { InlineMessage(text: error).padding(.top, 8) }
                    }
                    .padding(20)
                }
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom) {
                    BottomActions {
                        PassButton(title: "Send report", variant: .red, isLoading: sending) { Task { await send() } }
                        PassButton(title: "Cancel", variant: .surface) { dismiss() }
                    }
                    .background(PassColor.background)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func send() async {
        guard !sending else { return }
        switch Validators.reportDetails(details) {
        case .failure(let e): error = e.message; return
        case .success(let d):
            sending = true
            defer { sending = false }
            if await submit(reason, d) { dismiss() } else { error = "Couldn't send the report. Please try again." }
        }
    }
}
