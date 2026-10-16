import SwiftUI

/// Figma "Post-Reveal" (spec §23): collage, title, Share Relay, Save Video, Watch Again, Start Another Relay.
struct PostRevealView: View {
    @State var model: RevealViewModel
    @Environment(AppRouter.self) private var router
    @State private var share: ShareItems?
    @State private var showReport = false

    var body: some View {
        PassScreen {
            VStack(spacing: 0) {
                PassNavRow(backLabel: "Home", onBack: router.popToRoot)
                switch model.phase {
                case .loading: LoadingStateView()
                case .failed(let e): ErrorStateView(message: e.userMessage) { Task { await model.load() } }
                case .noReveal: ErrorStateView(message: "This Relay doesn't have a Reveal.")
                case .ready: if let m = model.manifest { content(m) }
                }
            }
        }
        .task { await model.load() }
        .shareSheet($share)
        .sheet(isPresented: $showReport) {
            ReportSheet(title: "Report this Reveal", target: .relay(model.relayID)) { r, d in await model.reportRelay(reason: r, details: d) }
        }
        .navigationBarBackButtonHidden(true)
    }

    private func content(_ m: RevealManifest) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        ForEach(Array(m.items.enumerated()), id: \.element.id) { i, item in
                            ZStack { if let img = model.media.images[i] { Image(uiImage: img).resizable().scaledToFill() } else { Color(hexString: item.colorHex) } }
                                .frame(maxWidth: .infinity).frame(height: 100).clipped().opacity(0.62)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.groupName).inter(12).foregroundStyle(PassColor.text(0.38))
                        Text("\(m.challengeTitle) — \(m.passedCount)/\(m.participantCount) PASSED 🔥").outfit(19, .heavy, tracking: -0.5).foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 16)
                    .background(LinearGradient(colors: [PassColor.card.opacity(0), PassColor.card], startPoint: .top, endPoint: .center))
                    .padding(.top, -44)
                }
                .passCard(radius: 22).clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .padding(.bottom, 22)

                if let p = model.exportProgress {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Building your video…").inter(13, .medium).foregroundStyle(.white)
                            Spacer()
                            Text("\(Int(p * 100))%").inter(12).foregroundStyle(PassColor.text(0.4)).monospacedDigit()
                        }
                        ProgressView(value: p).tint(PassColor.violet)
                    }
                    .padding(14).passCard(radius: 14).padding(.bottom, 10)
                    .accessibilityIdentifier("post.exporting")
                }
                if let e = model.exportError { InlineMessage(text: e).padding(.bottom, 10) }
                if let s = model.saveMessage { InlineMessage(text: s, color: PassColor.green).padding(.bottom, 10) }

                HStack(spacing: 10) {
                    bigAction("📤", "Share Relay", "Send to your stories", PassColor.violet) { Task { await shareVideo(m) } }
                        .accessibilityIdentifier("post.share")
                    bigAction("💾", "Save Video", "Save to camera roll", PassColor.blue) { Task { await model.saveToPhotos() } }
                        .accessibilityIdentifier("post.save")
                }
                .disabled(model.isExporting)
                .padding(.bottom, 10)
                rowAction("🔁", "Watch Again", "Replay the full reveal", PassColor.orange, action: model.watchAgain)
                    .accessibilityIdentifier("post.watchAgain")
                rowAction("🔥", "Start Another Relay", "New challenge · same crew", PassColor.red, action: model.startAnother)
                    .accessibilityIdentifier("post.startAnother")
                HStack {
                    Spacer()
                    Button { showReport = true } label: { Text("Report this Reveal").inter(12).foregroundStyle(PassColor.text(0.3)) }
                    Spacer()
                }
                .padding(.top, 6)
                Text("No public profile. No followers. Just your crew.").inter(12).foregroundStyle(PassColor.text(0.18))
                    .frame(maxWidth: .infinity).padding(.top, 8).padding(.bottom, 30)
            }
            .padding(.horizontal, 20)
        }
    }

    private func shareVideo(_ m: RevealManifest) async {
        do {
            let url = try await model.exportIfNeeded()
            share = ShareItems(items: [url, "PASS Relay · \(m.groupName) — \(m.challengeTitle) \(m.passedCount)/\(m.participantCount) PASSED 🔥"])
        } catch {}
    }

    private func bigAction(_ emoji: String, _ title: String, _ sub: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Text(emoji).font(.system(size: 20)).frame(width: 42, height: 42).background(color.opacity(0.2), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).outfit(15, .bold).foregroundStyle(.white)
                    Text(sub).inter(12).foregroundStyle(PassColor.text(0.4))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(16).passTintedCard(color, fill: 0.12, border: 0.28, radius: 18)
        }
        .buttonStyle(PressableRowStyle())
    }

    private func rowAction(_ emoji: String, _ title: String, _ sub: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(emoji).font(.system(size: 22)).frame(width: 44, height: 44).background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).outfit(16, .bold).foregroundStyle(.white)
                    Text(sub).inter(13).foregroundStyle(PassColor.text(0.4))
                }
                Spacer()
                ChevronRight()
            }
            .padding(.horizontal, 18).padding(.vertical, 16).passTintedCard(color, fill: 0.06, border: 0.15, radius: 18)
        }
        .buttonStyle(PressableRowStyle())
        .padding(.bottom, 10)
    }
}
