import SwiftUI

extension View {
    /// `.card` from the Figma: #161616 fill, 1 px white 7 % border, radius 20 (14 for `.card-sm`).
    func passCard(radius: CGFloat = 20, fill: Color = PassColor.card, border: Color = PassColor.cardBorder) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(border, lineWidth: 1).allowsHitTesting(false))
    }

    /// Tinted card (e.g. violet 10 % fill, violet 22 % border) used for the active-relay and selected states.
    func passTintedCard(_ color: Color, fill: Double = 0.1, border: Double = 0.22, radius: CGFloat = 20) -> some View {
        passCard(radius: radius, fill: color.opacity(fill), border: color.opacity(border))
    }

    /// Dashed "+ New …" rows.
    func passDashedCard(_ color: Color, fill: Double = 0.06, border: Double = 0.25, radius: CGFloat = 14) -> some View {
        background(color.opacity(fill), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(color.opacity(border))
                .allowsHitTesting(false))
    }
}
