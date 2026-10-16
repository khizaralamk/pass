import SwiftUI

/// Figma "Pass Baton" (spec §13): only members who haven't gone and aren't out; one pick; "Pass the Baton 🔥".
struct PassBatonView: View {
    @State var model: RelayViewModel
    @Environment(AppRouter.self) private var router

    var body: some View {
        PassScreen {
            VStack(spacing: 0) {
                PassNavRow(backLabel: nil, onBack: nil, onHome: router.popToRoot)
                switch model.relay {
                case .idle, .loading: LoadingStateView()
                case .failed(let e): ErrorStateView(message: e.userMessage) { Task { await model.load() } }
                case .loaded(let r): content(r)
                }
            }
        }
        .task { await model.load() }
        .task { await model.observeChanges() }
        .onChange(of: model.relay) { _, new in
            // If the deadline passed while choosing, the engine moved the Baton on: show progress instead.
            if let r = new.value, let me = model.me, !(r.isActive && r.isHolder(me)) { router.replaceStack(with: [.progress(r.id)]) }
        }
        .navigationBarBackButtonHidden(true)
    }

    private func content(_ r: Relay) -> some View {
        let eligible = model.eligibleNext
        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Eyebrow(text: "Who's next?", size: 12, opacity: 0.38).padding(.bottom, 6)
                    Text("Pass the Baton").outfit(36, .black, tracking: -1.5).foregroundStyle(.white).accessibilityAddTraits(.isHeader)
                    Text("\(r.groupName) · \(eligible.count) member\(eligible.count == 1 ? "" : "s") remaining").inter(14).foregroundStyle(PassColor.text(0.45))
                        .padding(.top, 6).padding(.bottom, 22)
                    VStack(spacing: 10) {
                        ForEach(eligible) { p in
                            let sel = model.selectedNext == p.id
                            let color = Color(hexString: p.user.colorHex)
                            Button { model.selectedNext = p.id; Haptics.light() } label: {
                                HStack(spacing: 14) {
                                    AvatarView(initials: p.user.initials, color: color, size: 46)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(p.user.displayName).outfit(18, .bold, tracking: -0.3).foregroundStyle(.white)
                                        Text("Hasn't gone yet").inter(13).foregroundStyle(PassColor.text(0.4))
                                    }
                                    Spacer()
                                    ZStack {
                                        Circle().fill(sel ? color : PassColor.text(0.08))
                                        if !sel { Circle().strokeBorder(PassColor.text(0.18), lineWidth: 1.5) }
                                        if sel { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white) }
                                    }
                                    .frame(width: 24, height: 24)
                                }
                                .padding(.horizontal, 18).padding(.vertical, 16)
                                .passCard(radius: 18, fill: sel ? color.opacity(0.1) : PassColor.card, border: sel ? color.opacity(0.3) : PassColor.cardBorder)
                            }
                            .buttonStyle(PressableRowStyle())
                            .accessibilityAddTraits(sel ? .isSelected : [])
                            .accessibilityIdentifier("pass.member.\(p.id.raw)")
                        }
                    }
                    if eligible.isEmpty {
                        Text("Everyone else has gone or is out of this Relay. Hang tight, PASS is wrapping it up.")
                            .inter(14).foregroundStyle(PassColor.text(0.5)).padding(16).passCard(radius: 14)
                    }
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(PassColor.green)
                        Text("Your submission is locked in").inter(13).foregroundStyle(PassColor.text(0.5))
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12).passCard(radius: 14).padding(.top, 16)
                    if let e = model.actionError { InlineMessage(text: e).padding(.top, 12) }
                }
                .padding(.horizontal, 20)
            }
            BottomActions {
                PassButton(title: "Pass the Baton 🔥", variant: .red, isLoading: model.isWorking) { Task { await model.pass() } }
                    .disabled(model.selectedNext == nil)
                    .accessibilityIdentifier("pass.confirm")
            }
        }
    }
}
