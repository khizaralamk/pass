import SwiftUI

/// Spec §3/§5: a person who installed PASS without the link enters the group code. Reached from Home/Profile and offered
/// when a deep link could not be parsed. `PasteButton` avoids the paste-permission alert.
struct InviteCodeEntryView: View {
    let deps: AppDependencies
    @Environment(AppRouter.self) private var router
    @State private var code = ""
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        PassScreen {
            VStack(spacing: 0) {
                PassNavRow(backLabel: "Back", onBack: router.pop)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Got an\ninvite code?").outfit(36, .black, tracking: -1.5).foregroundStyle(.white)
                            .padding(.bottom, 6).accessibilityAddTraits(.isHeader)
                        Text("Ask your friend for their group code. It looks like PASS-AB12.").inter(14).foregroundStyle(PassColor.text(0.4))
                            .padding(.bottom, 26)
                        SectionLabel(label: "Group code")
                        PassTextField(text: $code, placeholder: "PASS-", error: error, limit: 12, font: PassFont.outfit(24, .black))
                            .focused($focused)
                            .textInputAutocapitalization(.characters)
                            .keyboardType(.asciiCapable)
                            .submitLabel(.go)
                            .onSubmit(submit)
                            .accessibilityIdentifier("invite.code")
                        if let error { InlineMessage(text: error).padding(.top, 8) }
                        PasteButton(payloadType: String.self) { strings in
                            if let s = strings.first { code = s; error = nil }
                        }
                        .buttonBorderShape(.capsule)
                        .labelStyle(.titleAndIcon)
                        .tint(PassColor.surface)
                        .padding(.top, 14)
                    }
                    .padding(.horizontal, 20)
                }
                .scrollDismissesKeyboard(.interactively)
                BottomActions {
                    PassButton(title: "Open invite →", action: submit).disabled(Validators.normalized(code).isEmpty)
                        .accessibilityIdentifier("invite.open")
                }
            }
        }
        .onAppear { focused = true }
    }

    private func submit() {
        switch Validators.inviteCode(code) {
        case .success(let c):
            error = nil
            router.pop()
            router.fullScreen = .invite(code: c)
        case .failure(let e):
            error = e.message
        }
    }
}
