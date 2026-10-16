import SwiftUI

/// Figma "Relay Progress" (spec §14): names and status only, never media. Adds the timer, deferred/excluded states,
/// and the ended/cancelled banners (spec §11, §17).
struct RelayProgressView: View {
    @State var model: RelayViewModel
    @Environment(AppRouter.self) private var router
    @State private var reportRelay = false

    var body: some View {
        PassScreen {
            VStack(spacing: 0) {
                PassNavRow(backLabel: "Back", onBack: router.pop, onHome: router.popToRoot)
                switch model.relay {
                case .idle, .loading: LoadingStateView()
                case .failed(let e): ErrorStateView(message: e.userMessage) { Task { await model.load() } }
                case .loaded(let r): content(r)
                }
            }
        }
        .task { await model.load() }
        .task { await model.observeChanges() }
        .onChange(of: model.relay) { old, new in
            guard let r = new.value else { return }
            // Spec §16: when the relay completes with a Reveal, go straight to "Your relay is ready".
            if r.hasReveal, old.value?.hasReveal != true { router.replaceStack(with: [.relayComplete(r.id)]) }
        }
        .onAppear { if let r = model.current, r.hasReveal { router.replaceStack(with: [.relayComplete(r.id)]) } }
    }

    private func content(_ r: Relay) -> some View {
        let done = r.submittedCount, total = r.participantCount
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Relay Progress").outfit(30, .black, tracking: -1.2).foregroundStyle(.white).padding(.bottom, 4)
                    .accessibilityAddTraits(.isHeader)
                Text("\(r.groupName) · \(r.challengeTitle)").inter(14).foregroundStyle(PassColor.text(0.42)).padding(.bottom, 18)

                if !r.isActive { endedBanner(r).padding(.bottom, 16) }

                HStack(spacing: 16) {
                    ProgressRing(fraction: total == 0 ? 0 : Double(done) / Double(total), label: "\(done)")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(done) of \(total) done").outfit(22, .heavy, tracking: -0.8).foregroundStyle(.white)
                        if r.isActive, let h = r.holder {
                            Text(h.id == model.me ? "You have the baton" : "\(h.user.firstName) has the baton").inter(13).foregroundStyle(PassColor.text(0.45))
                        } else {
                            Text(r.outcome == .complete ? "Everyone submitted" : "Relay ended").inter(13).foregroundStyle(PassColor.text(0.45))
                        }
                    }
                    Spacer()
                    if r.isActive {
                        VStack(alignment: .trailing, spacing: 4) {
                            StatusDotLabel(text: r.currentTurn?.isRescue == true ? "Rescue" : "Live")
                            if let d = r.currentTurn?.deadline { CountdownText(deadline: d, short: r.currentTurn?.isRescue == true) }
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 18).passCard().padding(.bottom, 20)

                SectionLabel(label: "Baton order")
                VStack(spacing: 8) {
                    ForEach(Array(r.orderedForProgress.enumerated()), id: \.element.id) { i, p in
                        participantRow(p, index: i, relay: r)
                    }
                }
                Text(r.isActive ? "Submissions stay hidden until all \(total) finish." : r.hasReveal ? "Watch the Reveal to see everything." : "Submissions from this Relay stay hidden.")
                    .inter(13).foregroundStyle(PassColor.text(0.25)).frame(maxWidth: .infinity).padding(.top, 16).padding(.bottom, 4)

                if r.isActive, let me = model.me, r.isHolder(me) {
                    PassButton(title: r.hasSubmitted(me) ? "Pass the Baton 🔥" : "Take your turn 🔥", variant: .red) {
                        router.replaceStack(with: [r.hasSubmitted(me) ? .passBaton(r.id) : .baton(r.id)])
                    }
                    .padding(.top, 12)
                }
                if !r.isActive {
                    PassButton(title: "Start Another Relay", variant: .surface, action: model.startAnother).padding(.top, 12)
                }
                if model.demoAvailable && r.isActive { demoControls(r) }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .refreshable { await model.load(showLoading: false) }
    }

    private func endedBanner(_ r: Relay) -> some View {
        let (emoji, title, body, color): (String, String, String, Color) = {
            switch r.outcome {
            case .cancelled: return ("🚫", "Relay ended", r.endedReason ?? "Relay ended because a member left the group.", PassColor.amber)
            case .failed: return ("💤", "No Reveal this time", "Fewer than \(model.rules.minSubmissionsForReveal) people submitted, so the Relay ended without a Reveal. The streak is reset.", PassColor.red)
            case .failedWithReveal: return ("🔥", "Reveal is ready", "Not everyone made it, but \(r.submittedCount) did.", PassColor.green)
            case .complete: return ("🎉", "Your relay is ready", "Everyone submitted.", PassColor.green)
            case nil: return ("", "", "", .clear)
            }
        }()
        return HStack(alignment: .top, spacing: 12) {
            Text(emoji).font(.system(size: 22))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).outfit(16, .heavy).foregroundStyle(.white)
                Text(body).inter(13).foregroundStyle(PassColor.text(0.6)).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16).passTintedCard(color, radius: 16)
        .accessibilityElement(children: .combine)
    }

    private func participantRow(_ p: RelayParticipant, index: Int, relay: Relay) -> some View {
        let color = Color(hexString: p.user.colorHex)
        let isHolder = p.state == .holding && relay.isActive
        return HStack(spacing: 12) {
            ZStack {
                switch p.state {
                case .submitted:
                    Circle().fill(PassColor.green)
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                case .holding where relay.isActive:
                    Circle().fill(color)
                    Text("🔥").font(.system(size: 13))
                case .deferred:
                    Circle().fill(PassColor.amber.opacity(0.2))
                    Text("⏳").font(.system(size: 12))
                case .excluded:
                    Circle().fill(PassColor.red.opacity(0.2))
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(PassColor.red)
                default:
                    Circle().fill(PassColor.text(0.08))
                    Text("\(index + 1)").outfit(12, .bold).foregroundStyle(PassColor.text(0.35))
                }
            }
            .frame(width: 28, height: 28)
            AvatarView(initials: p.user.initials, color: color, size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(p.id == model.me ? "You" : p.user.displayName).outfit(16, .bold).foregroundStyle(.white)
                Text(statusText(p, relay)).inter(13).foregroundStyle(statusColor(p, relay))
            }
            Spacer()
            if isHolder, let d = relay.currentTurn?.deadline { CountdownText(deadline: d, short: relay.currentTurn?.isRescue == true) }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .passCard(radius: 16, fill: isHolder ? color.opacity(0.08) : PassColor.card, border: isHolder ? color.opacity(0.25) : PassColor.cardBorder)
        .accessibilityElement(children: .combine)
    }

    private func statusText(_ p: RelayParticipant, _ r: Relay) -> String {
        switch p.state {
        case .submitted: return r.hasReveal ? "Submitted" : "Submitted · hidden 🔒"
        case .holding: return r.isActive ? (r.currentTurn?.isRescue == true ? "Rescue window · last chance" : "Has the baton") : "Waiting…"
        case .deferred: return "Dropped the baton · one more chance later"
        case .excluded: return "Missed both chances"
        case .waiting: return r.isActive ? "Waiting…" : "Didn't get a turn"
        }
    }

    private func statusColor(_ p: RelayParticipant, _ r: Relay) -> Color {
        switch p.state {
        case .submitted: return PassColor.green
        case .holding: return PassColor.text(0.6)
        case .deferred: return PassColor.amber
        case .excluded: return PassColor.red.opacity(0.8)
        case .waiting: return PassColor.text(0.32)
        }
    }

    private func demoControls(_ r: Relay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(label: "Demo controls (mock backend)").padding(.top, 24)
            if let h = r.holder, h.id != model.me {
                PassButton(title: "\(h.user.firstName) submits and passes on", variant: .outline, height: 40, fontSize: 13) { Task { await model.demoNextMemberGoes() } }
                    .accessibilityIdentifier("demo.nextMember")
            }
            HStack(spacing: 8) {
                PassButton(title: "Holder drops the Baton", variant: .outline, height: 40, fontSize: 13) { Task { await model.demoHolderDrops() } }
                    .accessibilityIdentifier("demo.drop")
                PassButton(title: "Skip 2 hours", variant: .outline, height: 40, fontSize: 13) { Task { await model.demoAdvance(2 * 3600 + 1) } }
            }
            if let e = model.actionError { InlineMessage(text: e) }
            Text("Stands in for the other members' phones and the server clock. Not in release builds.").inter(11).foregroundStyle(PassColor.text(0.25))
        }
    }
}
