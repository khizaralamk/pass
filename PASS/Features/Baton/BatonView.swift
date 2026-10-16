import SwiftUI

/// Figma "Baton + Challenge" (spec §10) plus the rescue variant (spec §11, not in the Figma).
struct BatonView: View {
    @State var model: RelayViewModel
    @Environment(AppRouter.self) private var router
    @Environment(\.dependencies) private var deps

    var body: some View {
        PassScreen {
            VStack(spacing: 0) {
                PassNavRow(backLabel: "Home", onBack: router.popToRoot)
                switch model.relay {
                case .idle, .loading: LoadingStateView()
                case .failed(let e): ErrorStateView(message: e.userMessage) { Task { await model.load() } }
                case .loaded(let r): content(r)
                }
            }
        }
        .task { await model.load() }
        .task { await model.observeChanges() }
        .onChange(of: model.relay) { _, new in redirectIfNeeded(new.value) }
    }

    /// The Baton can move while this screen is open (deadline passed, or I already submitted): follow it.
    private func redirectIfNeeded(_ relay: Relay?) {
        guard let relay, let me = model.me else { return }
        if !relay.isActive || !relay.isHolder(me) { router.replaceStack(with: [.progress(relay.id)]) }
        else if relay.hasSubmitted(me) { router.replaceStack(with: [.passBaton(relay.id)]) }
    }

    private func content(_ r: Relay) -> some View {
        let rescue = r.currentTurn?.isRescue == true
        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        if let passer = r.passer {
                            AvatarView(initials: passer.initials, color: Color(hexString: passer.colorHex), size: 26)
                            Text("\(passer.firstName) passed you the baton").inter(14).foregroundStyle(PassColor.text(0.5))
                        } else {
                            Text("🔥").font(.system(size: 20))
                            Text("You started this relay").inter(14).foregroundStyle(PassColor.text(0.5))
                        }
                    }
                    .padding(.bottom, 20)
                    if rescue {
                        HStack(spacing: 8) {
                            StatusDotLabel(text: "Last chance")
                            Text("· final \(Int(model.rules.rescueWindow / 60))-minute window").inter(12).foregroundStyle(PassColor.red.opacity(0.8))
                        }
                        .padding(.bottom, 8)
                    } else {
                        Eyebrow(text: "Your challenge · \(r.groupName)", size: 12, opacity: 0.38).padding(.bottom, 8)
                    }
                    Text(r.challengeTitle).outfit(54, .black, tracking: -2.5).foregroundStyle(.white).lineSpacing(-5).padding(.bottom, 22)
                        .accessibilityAddTraits(.isHeader)
                    if rescue {
                        Text("You dropped the Baton earlier. Submit now to rescue the Relay and keep the streak alive.")
                            .inter(14).foregroundStyle(PassColor.text(0.6)).padding(.horizontal, 16).padding(.vertical, 12)
                            .passTintedCard(PassColor.red, radius: 14).padding(.bottom, 14)
                    }
                    HStack(spacing: 8) {
                        PillTag(text: "📸 Photo or video")
                        PillTag(text: "⏱️ Up to \(Int(model.rules.maxVideoSeconds)) sec")
                        PillTag(text: "🙈 No filters")
                    }
                    .padding(.bottom, 14)
                    HStack(spacing: 10) {
                        Text("👁️").font(.system(size: 18))
                        Text("Hidden until all \(r.participantCount) submit").inter(14).foregroundStyle(PassColor.text(0.6))
                    }
                    .padding(.horizontal, 16).padding(.vertical, 13).passCard(radius: 14).padding(.bottom, 16)
                    countdownCard(r, rescue: rescue)
                }
                .padding(.horizontal, 20)
            }
            BottomActions {
                if let e = model.actionError { InlineMessage(text: e) }
                PassButton(title: "Open Camera →", variant: rescue ? .red : .violet, action: model.openCamera)
                    .accessibilityIdentifier("baton.openCamera")
            }
        }
    }

    private func countdownCard(_ r: Relay, rescue: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: "Submit within", size: 12, opacity: 0.4)
            if let deadline = r.currentTurn?.deadline {
                CountdownText(deadline: deadline, short: rescue, font: PassFont.outfit(50, .black), color: .white)
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let elapsed = model.windowFraction(now: deps?.clock.now() ?? Date())
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(PassColor.text(0.08))
                            Capsule().fill(PassColor.red).frame(width: geo.size.width * (1 - elapsed))
                        }
                    }
                    .frame(height: 3)
                }
                .padding(.top, 8)
                .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 22).padding(.vertical, 20).passCard()
    }
}
