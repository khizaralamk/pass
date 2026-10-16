import SwiftUI

/// Figma motion: fade-up 0.42 s, scale-in 0.38 s, screen-in 0.35 s, ease cubic-bezier(0.22, 1, 0.36, 1), stagger 0.08 s.
enum PassMotion {
    static func ease(_ duration: Double) -> Animation {
        .timingCurve(0.22, 1, 0.36, 1, duration: duration)
    }
    static let fadeUp = ease(0.42)
    static let scaleIn = ease(0.38)
    static let screenIn = ease(0.35)
    static let stagger = 0.08
}

private struct FadeUpModifier: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 14)
            .onAppear {
                guard !shown else { return }
                withAnimation(PassMotion.fadeUp.delay(Double(index) * PassMotion.stagger)) { shown = true }
            }
    }
}

private struct ScaleInModifier: ViewModifier {
    let delay: Double
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .scaleEffect(shown || reduceMotion ? 1 : 0.93)
            .onAppear {
                guard !shown else { return }
                withAnimation(PassMotion.scaleIn.delay(delay)) { shown = true }
            }
    }
}

extension View {
    /// `.anim-fade-up .dN`: fades in from 14 pt below, staggered by `index`. Respects Reduce Motion.
    func fadeUp(_ index: Int = 0) -> some View { modifier(FadeUpModifier(index: index)) }
    /// `.anim-scale-in`.
    func scaleIn(delay: Double = 0) -> some View { modifier(ScaleInModifier(delay: delay)) }
}
