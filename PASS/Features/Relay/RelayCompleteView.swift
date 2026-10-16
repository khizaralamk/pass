import SwiftUI

/// Figma "Relay Complete" (spec §16): 🎉, "Your relay is ready.", avatars with ticks, "Watch the Reveal →". Nothing in between.
struct RelayCompleteView: View {
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
        .navigationBarBackButtonHidden(true)
    }

    private func content(_ r: Relay) -> some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 0) {
                Text("🎉").font(.system(size: 44))
                    .frame(width: 88, height: 88)
                    .background(PassColor.tile, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(PassColor.text(0.08), lineWidth: 1))
                    .padding(.bottom, 28).scaleIn()
                Text("Your relay\nis ready.").outfit(48, .black, tracking: -2.5).foregroundStyle(.white).multilineTextAlignment(.center).lineSpacing(-4)
                    .accessibilityAddTraits(.isHeader)
                Text(r.outcome == .complete ? "All \(r.participantCount) members submitted.\nTime to see what everyone dropped."
                     : "\(r.submittedCount) of \(r.participantCount) members submitted.\nTime to see what everyone dropped.")
                    .inter(15).foregroundStyle(PassColor.textSecondary).multilineTextAlignment(.center).lineSpacing(5).padding(.top, 14)
                HStack(spacing: 8) {
                    ForEach(r.participants.filter { $0.hasSubmitted }) { p in
                        AvatarView(initials: p.user.initials, color: Color(hexString: p.user.colorHex), size: 44)
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                                    .frame(width: 18, height: 18).background(PassColor.green, in: Circle())
                                    .overlay(Circle().strokeBorder(PassColor.background, lineWidth: 2))
                                    .offset(x: 2, y: 2)
                            }
                    }
                }
                .padding(.top, 28)
            }
            .padding(.horizontal, 28)
            .fadeUp()
            Spacer()
            BottomActions {
                PassButton(title: "Watch the Reveal →", variant: .red, action: model.watchReveal)
                    .accessibilityIdentifier("complete.watch")
            }
        }
    }
}
