import SwiftUI
import Observation

/// Spec §24: completed relays stay accessible to the group. Basic list → Reveal.
@MainActor
@Observable
final class RelayHistoryViewModel {
    let groupID: GroupID
    private(set) var relays: Loadable<[Relay]> = .idle
    private let deps: AppDependencies

    init(groupID: GroupID, deps: AppDependencies) {
        self.groupID = groupID
        self.deps = deps
    }

    func load() async {
        if relays.value == nil { relays = .loading }
        do { relays = .loaded(try await deps.relays.history(groupID: groupID)) }
        catch { let e = AppError.wrap(error); if !e.isCancellation, relays.value == nil { relays = .failed(e) } }
    }

    func open(_ relay: Relay) {
        if relay.hasReveal { deps.router.fullScreen = .reveal(relay.id) }
    }
}

struct RelayHistoryView: View {
    @State var model: RelayHistoryViewModel
    @Environment(AppRouter.self) private var router

    var body: some View {
        PassScreen {
            VStack(spacing: 0) {
                PassNavRow(backLabel: "Back", onBack: router.pop)
                switch model.relays {
                case .idle, .loading: LoadingStateView()
                case .failed(let e): ErrorStateView(message: e.userMessage) { Task { await model.load() } }
                case .loaded(let relays): list(relays)
                }
            }
        }
        .task { await model.load() }
    }

    private func list(_ relays: [Relay]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Past Relays").outfit(36, .black, tracking: -1.5).foregroundStyle(.white).padding(.bottom, 22)
                    .accessibilityAddTraits(.isHeader)
                if relays.isEmpty {
                    VStack(spacing: 8) {
                        Text("🎞️").font(.system(size: 40))
                        Text("No Relays yet").outfit(20, .heavy).foregroundStyle(PassColor.text(0.55))
                        Text("Finished Relays and their Reveals show up here.").inter(13).foregroundStyle(PassColor.text(0.3))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 40)
                } else {
                    VStack(spacing: 8) {
                        ForEach(relays) { r in
                            Button { model.open(r) } label: { row(r) }
                                .buttonStyle(PressableRowStyle())
                                .disabled(!r.hasReveal)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func row(_ r: Relay) -> some View {
        HStack(spacing: 12) {
            ZStack {
                if r.hasReveal, let first = r.submissionsInOrder.first {
                    MediaImageView(fileName: first.fileName) { PassColor.surfaceAlt }
                } else {
                    PassColor.surfaceAlt
                    Text(r.outcome == .cancelled ? "🚫" : "💤").font(.system(size: 18))
                }
            }
            .frame(width: 48, height: 64).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(r.challengeTitle).outfit(15, .bold).foregroundStyle(.white).lineLimit(1)
                Text(subtitle(r)).inter(12).foregroundStyle(outcomeColor(r))
                if let d = r.endedAt { Text(PassFormatters.relayDate.string(from: d)).inter(11).foregroundStyle(PassColor.text(0.3)) }
            }
            Spacer()
            if r.hasReveal { Image(systemName: "play.fill").font(.system(size: 13)).foregroundStyle(PassColor.text(0.5)) }
        }
        .padding(12).passCard(radius: 14)
        .accessibilityElement(children: .combine)
    }

    private func subtitle(_ r: Relay) -> String {
        switch r.outcome {
        case .complete: return "\(r.submittedCount)/\(r.participantCount) PASSED 🔥"
        case .failedWithReveal: return "\(r.submittedCount)/\(r.participantCount) PASSED · streak reset"
        case .failed: return "Ended without a Reveal"
        case .cancelled: return r.endedReason ?? "Relay ended"
        case nil: return "In progress"
        }
    }

    private func outcomeColor(_ r: Relay) -> Color {
        switch r.outcome {
        case .complete: return PassColor.green
        case .failedWithReveal: return PassColor.amber
        default: return PassColor.text(0.4)
        }
    }
}
