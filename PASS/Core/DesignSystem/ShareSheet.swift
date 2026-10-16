import SwiftUI
import UIKit

/// Native iOS share sheet (spec §5 invites, §23 Share Relay).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var onComplete: ((Bool) -> Void)? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.completionWithItemsHandler = { _, completed, _, _ in onComplete?(completed) }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct ShareItems: Identifiable {
    let id = UUID()
    let items: [Any]
}

extension View {
    func shareSheet(_ items: Binding<ShareItems?>, onComplete: ((Bool) -> Void)? = nil) -> some View {
        sheet(item: items) { payload in
            ShareSheet(items: payload.items, onComplete: onComplete)
                .presentationDetents([.medium, .large])
                .ignoresSafeArea()
        }
    }
}
