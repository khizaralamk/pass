import SwiftUI

/// Outfit (display) and Inter (body) are bundled as variable fonts (Resources/Fonts).
/// Sizes come from the Figma; `relativeTo:` keeps them scaling with Dynamic Type.
enum PassFont {
    static let displayFamily = "Outfit"
    static let bodyFamily = "Inter"

    static func outfit(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        Font.custom(displayFamily, size: size, relativeTo: textStyle(for: size)).weight(weight)
    }

    static func inter(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        Font.custom(bodyFamily, size: size, relativeTo: textStyle(for: size)).weight(weight)
    }

    /// Large display sizes scale less aggressively than body text so headlines stay on screen at accessibility sizes.
    private static func textStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<13: return .caption
        case ..<16: return .footnote
        case ..<20: return .body
        case ..<28: return .title3
        case ..<40: return .title
        default: return .largeTitle
        }
    }
}

extension Text {
    /// Outfit text with Figma letter-spacing (tracking in points).
    func outfit(_ size: CGFloat, _ weight: Font.Weight = .bold, tracking: CGFloat = 0) -> Text {
        self.font(PassFont.outfit(size, weight)).tracking(tracking)
    }

    /// Inter text with optional tracking. Pass `uppercase: true` for the Figma's small caps labels (0.08–0.12 em).
    func inter(_ size: CGFloat, _ weight: Font.Weight = .regular, tracking: CGFloat = 0) -> Text {
        self.font(PassFont.inter(size, weight)).tracking(tracking)
    }
}

extension View {
    func outfitFont(_ size: CGFloat, _ weight: Font.Weight = .bold) -> some View {
        font(PassFont.outfit(size, weight))
    }

    func interFont(_ size: CGFloat, _ weight: Font.Weight = .regular) -> some View {
        font(PassFont.inter(size, weight))
    }
}
