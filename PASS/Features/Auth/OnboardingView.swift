import SwiftUI
import PhotosUI

/// Spec §3 onboarding (not in the Figma; designed in its style): name → date of birth (16+) → optional photo → terms →
/// notifications. The profile is saved once, at the terms step, so a failure never leaves a half-saved account.
@MainActor
@Observable
final class OnboardingViewModel {
    enum Step: Int, CaseIterable { case name, birthday, photo, terms, notifications }

    var step: Step = .name
    var name = ""
    var birthday: Date
    var avatar: UIImage?
    var agreed = false
    var nameError: String?
    var birthdayError: String?
    var isUnderage = false
    var saveError: String?
    var isSaving = false

    private let deps: AppDependencies

    init(deps: AppDependencies) {
        self.deps = deps
        // Default the wheel to a plausible adult date rather than today, so the user scrolls less.
        birthday = Calendar.current.date(byAdding: .year, value: -20, to: deps.clock.now()) ?? deps.clock.now()
        if let n = deps.session.user?.displayName, n != "You" { name = n }
    }

    var canContinueName: Bool { !Validators.normalized(name).isEmpty }

    func submitName() {
        switch Validators.displayName(name) {
        case .success(let n): name = n; nameError = nil; step = .birthday
        case .failure(let e): nameError = e.message
        }
    }

    func submitBirthday() {
        switch Validators.dateOfBirth(birthday, now: deps.clock.now(), minimumAge: deps.configuration.rules.minimumAge) {
        case .success: birthdayError = nil; step = .photo
        case .failure(let e):
            if e.message.contains("or older") { isUnderage = true } else { birthdayError = e.message }
        }
    }

    func back() {
        guard let prev = Step(rawValue: step.rawValue - 1) else { return }
        step = prev
    }

    /// Saves the profile. On success moves to the notification step; the session stays in `.onboarding` until then.
    func acceptTerms() async {
        guard agreed, !isSaving else { return }
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        var avatarFile: String?
        if let avatar {
            let resized = avatar.resized(maxDimension: 512)
            avatarFile = try? deps.media.saveJPEG(resized, quality: 0.85, fileName: "avatar-\(UUID().uuidString.lowercased()).jpg")
        }
        let ok = await deps.session.completeOnboarding(displayName: name, dateOfBirth: birthday, avatarFileName: avatarFile)
        if ok { step = .notifications } else { saveError = deps.session.lastError?.userMessage }
    }

    func requestNotifications() async {
        _ = await deps.notifications.requestAuthorization()
        deps.sessionStore.notificationPromptShown = true
        finish()
    }

    func finish() {
        deps.sessionStore.notificationPromptShown = true
        deps.session.finishOnboarding()
    }
}

struct OnboardingView: View {
    @Environment(\.dependencies) private var deps
    @Environment(AppSession.self) private var session
    @State private var model: OnboardingViewModel?

    var body: some View {
        if let model {
            OnboardingContent(model: model)
        } else {
            Color.black.ignoresSafeArea().onAppear { if let deps { model = OnboardingViewModel(deps: deps) } }
        }
    }
}

private struct OnboardingContent: View {
    @Bindable var model: OnboardingViewModel
    @Environment(AppSession.self) private var session
    @Environment(\.dependencies) private var deps
    @FocusState private var nameFocused: Bool
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        PassScreen {
            if model.isUnderage {
                UnderageView(minimumAge: deps?.configuration.rules.minimumAge ?? 16)
            } else {
                flow
            }
        }
    }

    private var canGoBack: Bool { model.step != .name && model.step != .notifications }

    private var flow: some View {
        VStack(spacing: 0) {
            PassNavRow(backLabel: "Back", onBack: canGoBack ? { model.back() } : nil)
            stepIndicator
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    currentStep
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            actions
        }
        .animation(PassMotion.screenIn, value: model.step)
    }

    @ViewBuilder
    private var currentStep: some View {
        switch model.step {
        case .name: nameStep
        case .birthday: birthdayStep
        case .photo: photoStep
        case .terms: termsStep
        case .notifications: notificationsStep
        }
    }

    private var stepIndicator: some View {
        HStack(spacing: 4) {
            ForEach(OnboardingViewModel.Step.allCases, id: \.rawValue) { s in
                Capsule().fill(s.rawValue <= model.step.rawValue ? PassColor.violet : PassColor.text(0.1))
                    .frame(height: 3)
            }
        }
        .padding(.horizontal, 20).padding(.bottom, 20)
        .accessibilityLabel("Step \(model.step.rawValue + 1) of \(OnboardingViewModel.Step.allCases.count)")
    }

    private func title(_ t: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(t).outfit(36, .black, tracking: -1.5).foregroundStyle(.white).lineSpacing(-2)
                .accessibilityAddTraits(.isHeader)
            Text(sub).inter(14).foregroundStyle(PassColor.text(0.4))
        }
        .padding(.bottom, 26)
    }

    // MARK: Steps

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            title("What should we\ncall you?", "Your friends see this name on every Relay.")
            SectionLabel(label: "Display name")
            PassTextField(text: $model.name, placeholder: "e.g. Maya", error: model.nameError, limit: Validators.displayNameRange.upperBound)
                .focused($nameFocused)
                .submitLabel(.continue)
                .onSubmit(model.submitName)
                .textContentType(.name)
                .accessibilityIdentifier("onboarding.name")
            if let e = model.nameError { InlineMessage(text: e).padding(.top, 8) }
        }
        .onAppear { nameFocused = true }
    }

    private var birthdayStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            title("When's your\nbirthday?", "PASS is for people \(deps?.configuration.rules.minimumAge ?? 16) and older. We never show your birthday to anyone.")
            SectionLabel(label: "Date of birth")
            DatePicker("Date of birth", selection: $model.birthday, in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .colorScheme(.dark)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .passCard(radius: 16)
                .accessibilityIdentifier("onboarding.birthday")
            if let e = model.birthdayError { InlineMessage(text: e).padding(.top, 8) }
        }
    }

    private var photoStep: some View {
        VStack(alignment: .center, spacing: 0) {
            title("Add a photo", "Optional. Your friends already know your face.")
                .frame(maxWidth: .infinity, alignment: .leading)
            PhotosPicker(selection: $photoItem, matching: .images) {
                ZStack {
                    if let img = model.avatar {
                        Image(uiImage: img).resizable().scaledToFill()
                    } else {
                        AvatarView(initials: PassFormatters.initials(model.name), color: PassColor.violet, size: 120)
                    }
                }
                .frame(width: 120, height: 120)
                .clipShape(Circle())
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "camera.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 34, height: 34).background(PassColor.violet, in: Circle())
                        .overlay(Circle().strokeBorder(PassColor.background, lineWidth: 3))
                }
            }
            .accessibilityLabel(model.avatar == nil ? "Choose a profile photo" : "Change profile photo")
            .padding(.top, 12)
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                        model.avatar = img
                    }
                }
            }
            if model.avatar != nil {
                Button("Remove photo") { model.avatar = nil; photoItem = nil }
                    .font(PassFont.inter(13, .semibold)).foregroundStyle(PassColor.text(0.5)).padding(.top, 14)
            }
        }
    }

    private var termsStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            title("One last thing", "PASS is private by design. No feed, no followers, no strangers.")
            VStack(alignment: .leading, spacing: 14) {
                rule("🔒", "Submissions stay hidden until the Reveal.")
                rule("👀", "Only people in your groups can see your Relays.")
                rule("🚫", "Harassment or abusive content isn't tolerated. You can report or block anyone.")
            }
            .padding(18).passCard(radius: 16)
            .padding(.bottom, 16)
            Button { model.agreed.toggle() } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: model.agreed ? "checkmark.square.fill" : "square")
                        .font(.system(size: 22)).foregroundStyle(model.agreed ? PassColor.violet : PassColor.text(0.3))
                    (Text("I'm \(deps?.configuration.rules.minimumAge ?? 16) or older and I agree to the ")
                     + Text("Terms").foregroundColor(PassColor.violet) + Text(" and ")
                     + Text("Privacy Policy").foregroundColor(PassColor.violet) + Text("."))
                    .font(PassFont.inter(14)).foregroundStyle(PassColor.text(0.7))
                    .multilineTextAlignment(.leading)
                }
            }
            .accessibilityIdentifier("onboarding.agree")
            .accessibilityValue(model.agreed ? "Checked" : "Unchecked")
            HStack(spacing: 16) {
                if let deps {
                    Link("Read the Terms", destination: deps.configuration.termsURL)
                    Link("Privacy Policy", destination: deps.configuration.privacyPolicyURL)
                }
            }
            .font(PassFont.inter(13, .semibold)).foregroundStyle(PassColor.text(0.45))
            .padding(.top, 14).padding(.leading, 34)
            if let e = model.saveError { InlineMessage(text: e).padding(.top, 12) }
        }
    }

    private var notificationsStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            title("Don't drop\nthe Baton", "PASS sends a notification when it's your turn, when time is running out and when a Reveal is ready.")
            VStack(alignment: .leading, spacing: 14) {
                rule("🔥", "Maya passed you the Baton.")
                rule("⏳", "Your Baton is waiting.")
                rule("🎉", "Your Relay is ready.")
            }
            .padding(18).passCard(radius: 16)
        }
    }

    private func rule(_ emoji: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(emoji).font(.system(size: 18))
            Text(text).inter(14).foregroundStyle(PassColor.text(0.6)).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Actions

    @ViewBuilder
    private var actions: some View {
        BottomActions {
            switch model.step {
            case .name:
                PassButton(title: "Continue →", action: model.submitName).disabled(!model.canContinueName)
                    .accessibilityIdentifier("onboarding.continue")
            case .birthday:
                PassButton(title: "Continue →", action: model.submitBirthday).accessibilityIdentifier("onboarding.continue")
            case .photo:
                PassButton(title: model.avatar == nil ? "Skip for now" : "Continue →", variant: model.avatar == nil ? .surface : .violet) {
                    model.step = .terms
                }
                .accessibilityIdentifier("onboarding.continue")
            case .terms:
                PassButton(title: "Get started 🔥", variant: .red, isLoading: model.isSaving) { Task { await model.acceptTerms() } }
                    .disabled(!model.agreed)
                    .accessibilityIdentifier("onboarding.continue")
            case .notifications:
                PassButton(title: "Turn on notifications") { Task { await model.requestNotifications() } }
                    .accessibilityIdentifier("onboarding.notifications")
                PassButton(title: "Not now", variant: .surface, action: model.finish)
                    .accessibilityIdentifier("onboarding.notifications.skip")
            }
        }
    }
}

/// Spec §3: under 16 cannot use PASS. There is no way around it except signing out.
struct UnderageView: View {
    let minimumAge: Int
    @Environment(AppSession.self) private var session

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 16) {
                Text("🙈").font(.system(size: 54))
                Text("Not just yet").outfit(40, .black, tracking: -2).foregroundStyle(.white)
                Text("PASS is for people \(minimumAge) and older. Come back when you're \(minimumAge) and we'll save you a Baton.")
                    .inter(15).foregroundStyle(PassColor.textSecondary).multilineTextAlignment(.center).lineSpacing(4)
            }
            .padding(.horizontal, 28)
            Spacer()
            BottomActions {
                PassButton(title: "Sign out", variant: .surface) { Task { await session.signOut() } }
            }
        }
        .accessibilityIdentifier("onboarding.underage")
    }
}

/// Text input inside a Figma card (dark fill, violet border when it has text, Outfit 18).
struct PassTextField: View {
    @Binding var text: String
    let placeholder: String
    var error: String? = nil
    var limit: Int? = nil
    var font: Font = PassFont.outfit(18, .bold)

    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(PassColor.text(0.25)))
            .font(font)
            .foregroundStyle(.white)
            .tint(PassColor.violet)
            .autocorrectionDisabled()
            .padding(.horizontal, 18).padding(.vertical, 14)
            .passCard(radius: 16, border: error != nil ? PassColor.red.opacity(0.6) : (text.isEmpty ? PassColor.cardBorder : PassColor.violet.opacity(0.4)))
            .onChange(of: text) { _, new in
                if let limit, new.count > limit { text = String(new.prefix(limit)) }
            }
    }
}

extension UIImage {
    func resized(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return self }
        let scale = maxDimension / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
