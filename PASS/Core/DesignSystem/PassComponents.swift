import SwiftUI

// MARK: - Avatars

/// Coloured circle with initials (Figma `Avatar`). Size drives the font (34 % of the diameter).
struct AvatarView: View {
    let initials: String
    let color: Color
    var size: CGFloat = 44

    var body: some View {
        Text(initials)
            .font(PassFont.outfit((size * 0.34).rounded(), .heavy))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color, in: Circle())
            .accessibilityHidden(true)
    }
}

/// Overlapping avatars (Figma `AvatarStack`), at most 5.
struct AvatarStackView: View {
    let members: [(initials: String, color: Color)]
    var size: CGFloat = 28

    var body: some View {
        HStack(spacing: -(size * 0.28).rounded()) {
            ForEach(Array(members.prefix(5).enumerated()), id: \.offset) { index, m in
                AvatarView(initials: m.initials, color: m.color, size: size)
                    .overlay(Circle().strokeBorder(PassColor.background, lineWidth: 1.5))
                    .zIndex(Double(5 - index))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Labels and small bits

/// Uppercase section label (Inter 11, white 30 %, 0.1 em) with an optional trailing action.
struct SectionLabel: View {
    let label: String
    var action: String? = nil
    var onAction: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(label.uppercased()).inter(11, .regular, tracking: 1.1).foregroundStyle(PassColor.textMuted)
            Spacer()
            if let action, let onAction {
                Button(action: onAction) {
                    Text(action).inter(13, .semibold).foregroundStyle(PassColor.violet)
                }
            }
        }
        .padding(.bottom, 8)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Small uppercase eyebrow text (Inter 12–13, 0.08–0.12 em) used above headlines.
struct Eyebrow: View {
    let text: String
    var size: CGFloat = 12
    var opacity: Double = 0.38
    var body: some View {
        Text(text.uppercased()).inter(size, .regular, tracking: size * 0.09).foregroundStyle(PassColor.text(opacity))
    }
}

struct ChevronRight: View {
    var opacity: Double = 0.22
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(PassColor.text(opacity))
            .accessibilityHidden(true)
    }
}

/// Red live dot + label ("Live", "Your turn").
struct StatusDotLabel: View {
    let text: String
    var color: Color = PassColor.red
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text.uppercased()).inter(12, .semibold, tracking: 0.7).foregroundStyle(color)
        }
    }
}

/// Grey pill tag ("📸 Photo or video").
struct PillTag: View {
    let text: String
    var body: some View {
        Text(text).inter(13).foregroundStyle(PassColor.text(0.65))
            .padding(.horizontal, 13).padding(.vertical, 6)
            .background(PassColor.surfaceAlt, in: Capsule())
            .overlay(Capsule().strokeBorder(PassColor.cardBorder, lineWidth: 1))
    }
}

/// Small violet "You" badge.
struct YouBadge: View {
    var body: some View {
        Text("You").inter(12, .semibold).foregroundStyle(PassColor.violet)
            .padding(.horizontal, 10).padding(.vertical, 3)
            .background(PassColor.violet.opacity(0.14), in: Capsule())
    }
}

/// Emoji in a rounded dark tile (group icon).
struct EmojiTile: View {
    let emoji: String
    var size: CGFloat = 38
    var radius: CGFloat = 11
    var fill: Color = PassColor.surfaceAlt
    var body: some View {
        Text(emoji)
            .font(.system(size: size * 0.47))
            .frame(width: size, height: size)
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Brand tile with the "P" wordmark (splash, end card, notification icon).
struct BrandTile: View {
    var size: CGFloat = 88
    var body: some View {
        Text("P")
            .font(PassFont.outfit(size * 0.5, .black))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(PassColor.brandGradient, in: RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - Progress

/// Thin segmented bar, one segment per member (Figma relay cards).
struct MemberSegmentBar: View {
    struct Segment: Identifiable {
        let id: String
        let color: Color
    }
    let segments: [Segment]
    var height: CGFloat = 3
    var spacing: CGFloat = 4

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(segments) { s in
                Capsule().fill(s.color).frame(height: height)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Circular progress ring with a number inside (Relay Progress header).
struct ProgressRing: View {
    let fraction: Double
    let label: String
    var size: CGFloat = 54
    var color: Color = PassColor.violet

    var body: some View {
        ZStack {
            Circle().stroke(PassColor.text(0.08), lineWidth: 3.5)
            Circle()
                .trim(from: 0, to: max(0, min(1, fraction)))
                .stroke(color, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(label).outfit(16, .black).foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Navigation row

/// Figma `NavRow`: a text back button ("Home" / "Back") and an optional circular home button. 52 pt tall.
struct PassNavRow: View {
    var backLabel: String? = "Back"
    var onBack: (() -> Void)? = nil
    var onHome: (() -> Void)? = nil

    var body: some View {
        HStack {
            if let onBack {
                Button(action: onBack) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold))
                        if let backLabel { Text(backLabel).inter(15, .medium) }
                    }
                    .foregroundStyle(PassColor.text(0.75))
                    .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                }
                .accessibilityLabel(backLabel ?? "Back")
                .accessibilityIdentifier("nav.back")
            } else {
                Color.clear.frame(width: 36, height: 36)
            }
            Spacer()
            if let onHome {
                Button(action: onHome) {
                    Image(systemName: "house")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(PassColor.text(0.6))
                        .frame(width: 36, height: 36)
                        .background(PassColor.text(0.07), in: Circle())
                        .overlay(Circle().strokeBorder(PassColor.text(0.1), lineWidth: 1))
                }
                .accessibilityLabel("Home")
                .accessibilityIdentifier("nav.home")
            }
        }
        .frame(height: 52)
        .padding(.horizontal, 20)
    }
}

/// Translucent circular back button for photo screens (camera, preview).
struct PhotoPillButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(.black.opacity(0.55), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.1), lineWidth: 1))
        }
        .accessibilityLabel(label)
    }
}

// MARK: - Screen scaffolding

/// Full-screen dark background that ignores safe areas. Content lays out inside the safe area.
struct PassScreen<Content: View>: View {
    var background: Color = PassColor.background
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            content
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
    }
}

/// Bottom action area: 20 pt side padding and breathing room above the home indicator.
struct BottomActions<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 10) { content }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 14)
    }
}

// MARK: - State views

struct LoadingStateView: View {
    var text: String = "Loading…"
    var body: some View {
        VStack(spacing: 14) {
            ProgressView().tint(PassColor.text(0.6))
            Text(text).inter(14).foregroundStyle(PassColor.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct ErrorStateView: View {
    let message: String
    var retryTitle: String = "Try again"
    var onRetry: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            Text("⚠️").font(.system(size: 34))
            Text(message).inter(14).foregroundStyle(PassColor.textSecondary)
                .multilineTextAlignment(.center)
            if let onRetry {
                PassButton(title: retryTitle, variant: .surface, height: 46, fontSize: 14, fullWidth: false, action: onRetry)
                    .accessibilityIdentifier("error.retry")
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Inline validation / error message under a field or above a button.
struct InlineMessage: View {
    let text: String
    var color: Color = PassColor.red
    var body: some View {
        Text(text).inter(13).foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Error: \(text)")
    }
}

// MARK: - Toast

struct ToastMessage: Equatable, Identifiable {
    let id = UUID()
    let text: String
    var emoji: String? = nil
}

private struct ToastModifier: ViewModifier {
    @Binding var toast: ToastMessage?

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let toast {
                HStack(spacing: 8) {
                    if let emoji = toast.emoji { Text(emoji) }
                    Text(toast.text).inter(14, .medium).foregroundStyle(.white)
                }
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(PassColor.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(PassColor.text(0.1), lineWidth: 1))
                .padding(.bottom, 90)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: toast.id) {
                    try? await Task.sleep(for: .seconds(2.2))
                    withAnimation(PassMotion.screenIn) { self.toast = nil }
                }
                .accessibilityIdentifier("toast")
            }
        }
        .animation(PassMotion.screenIn, value: toast)
    }
}

extension View {
    func toast(_ toast: Binding<ToastMessage?>) -> some View { modifier(ToastModifier(toast: toast)) }
}
