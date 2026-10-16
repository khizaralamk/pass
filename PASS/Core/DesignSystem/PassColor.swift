import SwiftUI

/// Design tokens from the Figma Make prototype (docs/figma/FIGMA-NOTES.md). PASS is dark-only.
enum PassColor {
    // Surfaces
    static let background = Color(hex: 0x0D0D0D)
    static let backgroundDeep = Color(hex: 0x0A0A0A)
    static let card = Color(hex: 0x161616)
    static let cardBorder = Color.white.opacity(0.07)
    static let surface = Color(hex: 0x1C1C1E)
    static let surfaceAlt = Color(hex: 0x1E1E1E)
    static let tile = Color(hex: 0x1A1A1A)

    // Brand
    static let violet = Color(hex: 0x6B46FF)
    static let violetDeep = Color(hex: 0x4020CC)
    static let red = Color(hex: 0xFF2D55)
    static let orange = Color(hex: 0xFF6B35)
    static let amber = Color(hex: 0xFF9F0A)
    static let green = Color(hex: 0x30D158)
    static let blue = Color(hex: 0x0A84FF)
    static let purple = Color(hex: 0xBF5AF2)

    // Text levels used throughout the Figma (white at a given opacity)
    static let textPrimary = Color.white
    static let textStrong = Color.white.opacity(0.92)
    static let textSecondary = Color.white.opacity(0.5)
    static let textTertiary = Color.white.opacity(0.38)
    static let textMuted = Color.white.opacity(0.3)
    static let textFaint = Color.white.opacity(0.22)
    static func text(_ opacity: Double) -> Color { Color.white.opacity(opacity) }

    /// Brand gradient used by the splash tile and notification icon.
    static let brandGradient = LinearGradient(
        colors: [violet, red], startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Member avatar colours, assigned by join order (BUILD-PLAN 5.5.2).
    static let memberPaletteHex: [String] = ["#FF6B35", "#6B46FF", "#FF2D55", "#0A84FF", "#30D158", "#FF9F0A", "#BF5AF2"]
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }

    /// Parses "#RRGGBB" or "RRGGBB". Falls back to violet for malformed input so a bad fixture never crashes the UI.
    init(hexString: String, opacity: Double = 1) {
        var s = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else {
            self = PassColor.violet.opacity(opacity)
            return
        }
        self.init(hex: v, opacity: opacity)
    }
}
