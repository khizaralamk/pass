import SwiftUI

/// Figma buttons: 56 pt tall, full width, pill, Outfit 700 16; pressed = 80 % opacity + 0.975 scale; disabled = 30 % opacity.
enum PassButtonVariant {
    case violet, red, surface, outline, white

    var background: Color {
        switch self {
        case .violet: return PassColor.violet
        case .red: return PassColor.red
        case .surface: return PassColor.surface
        case .outline: return .clear
        case .white: return .white
        }
    }

    var foreground: Color {
        switch self {
        case .violet, .red: return .white
        case .surface: return PassColor.text(0.7)
        case .outline: return PassColor.text(0.6)
        case .white: return .black
        }
    }

    var border: Color? {
        switch self {
        case .surface: return PassColor.text(0.08)
        case .outline: return PassColor.text(0.14)
        default: return nil
        }
    }
}

struct PassButtonStyle: ButtonStyle {
    var variant: PassButtonVariant = .violet
    var height: CGFloat = 56
    var fontSize: CGFloat = 16
    var fullWidth = true
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PassFont.outfit(fontSize, .bold))
            .tracking(-0.1)
            .foregroundStyle(variant.foreground)
            .padding(.horizontal, 24)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: height)
            .background(variant.background, in: Capsule())
            .overlay {
                if let border = variant.border {
                    Capsule().strokeBorder(border, lineWidth: 1)
                }
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.3)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

/// Standard PASS call-to-action with an optional loading state. While loading the button is disabled, so a double tap cannot submit twice.
struct PassButton: View {
    let title: String
    var variant: PassButtonVariant = .violet
    var height: CGFloat = 56
    var fontSize: CGFloat = 16
    var fullWidth = true
    var isLoading = false
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                HStack(spacing: 10) {
                    if let systemImage {
                        Image(systemName: systemImage).font(.system(size: 18, weight: .semibold))
                    }
                    Text(title)
                }
                .opacity(isLoading ? 0 : 1)
                if isLoading {
                    ProgressView().tint(variant.foreground)
                }
            }
        }
        .buttonStyle(PassButtonStyle(variant: variant, height: height, fontSize: fontSize, fullWidth: fullWidth))
        .disabled(isLoading)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isLoading ? .updatesFrequently : [])
    }
}

/// Figma's bordered pressable rows (group rows, option rows). Scales slightly on press.
struct PressableRowStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
