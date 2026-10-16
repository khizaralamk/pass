import SwiftUI
import UIKit

/// Media the slides draw: decoded photos (and video poster frames for the recap) keyed by item index.
struct RevealMedia {
    var images: [Int: UIImage] = [:]
    var videoURLs: [Int: URL] = [:]
}

/// One Reveal frame, drawn purely from (segment, elapsed). The player and the exporter share this, so the exported
/// video looks exactly like the in-app playback. Sized to the given canvas; the Figma phone is 390 pt wide.
struct RevealSlideView: View {
    let manifest: RevealManifest
    let segment: RevealSegment
    let elapsed: TimeInterval
    let media: RevealMedia
    var canvas: CGSize
    var template: RevealTemplate = .standard
    /// Live video is drawn by the player underneath this view; the exporter passes the clip frame as an image.
    var videoFrame: UIImage? = nil

    private var scale: CGFloat { canvas.width / 390 }
    private func pt(_ v: CGFloat) -> CGFloat { v * scale }
    private var fadeIn: Double { min(1, max(0, elapsed / template.fade)) }

    var body: some View {
        ZStack {
            Color(hex: 0x0D0D0D)
            switch segment.kind {
            case .intro: intro
            case .participant(let i): participant(i)
            case .recap: recap
            case .passed: passed
            case .end: endCard
            }
            Color.black.opacity(1 - fadeIn)
        }
        .frame(width: canvas.width, height: canvas.height)
        .clipped()
    }

    private var intro: some View {
        VStack(spacing: pt(16)) {
            Text("\(manifest.items.count) submissions incoming".uppercased())
                .font(.custom(PassFont.bodyFamily, fixedSize: pt(13))).tracking(pt(1.5)).foregroundStyle(.white.opacity(0.38))
            Text(manifest.challengeTitle.uppercased())
                .font(.custom(PassFont.displayFamily, fixedSize: pt(56)).weight(.black)).tracking(pt(-2.5))
                .foregroundStyle(.white).multilineTextAlignment(.center).lineSpacing(pt(-4))
                .padding(.horizontal, pt(28))
        }
    }

    private func participant(_ i: Int) -> some View {
        let item = manifest.items[i]
        let nameProgress = min(1, max(0, (elapsed - template.nameDelay) / template.nameDuration))
        let eased = 1 - pow(1 - nameProgress, 3)
        let fadeOut: Double = segment.duration > 2.0 && elapsed > template.nameFadeOutAt ? max(0, 1 - (elapsed - template.nameFadeOutAt) / 0.3) : 1
        return ZStack(alignment: .bottomLeading) {
            if let frame = videoFrame {
                Image(uiImage: frame).resizable().scaledToFill().frame(width: canvas.width, height: canvas.height).clipped()
            } else if item.mediaType == .photo, let img = media.images[i] {
                Image(uiImage: img).resizable().scaledToFill().frame(width: canvas.width, height: canvas.height).clipped()
            } else if item.mediaType == .video {
                Color.clear // the player's AVPlayerLayer shows through
            } else {
                Color(hexString: item.colorHex).opacity(0.5)
            }
            Color.black.opacity(0.28)
            LinearGradient(stops: [.init(color: .clear, location: 0.2), .init(color: .black.opacity(0.3), location: 0.5), .init(color: .black.opacity(0.88), location: 1)],
                           startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: pt(4)) {
                Text("#\(item.position)").font(.custom(PassFont.bodyFamily, fixedSize: pt(14))).tracking(pt(1.4)).foregroundStyle(.white.opacity(0.55))
                Text(item.firstName).font(.custom(PassFont.displayFamily, fixedSize: pt(44)).weight(.black)).tracking(pt(-2)).foregroundStyle(.white)
            }
            .padding(.leading, pt(28)).padding(.bottom, pt(80))
            .opacity(eased * fadeOut)
            .offset(y: pt(10) * (1 - eased))
        }
    }

    private var recap: some View {
        VStack(spacing: pt(28)) {
            Text((manifest.outcome == .complete ? "All \(manifest.items.count) submitted" : "\(manifest.items.count) of \(manifest.participantCount) submitted").uppercased())
                .font(.custom(PassFont.bodyFamily, fixedSize: pt(13))).tracking(pt(1.5)).foregroundStyle(.white.opacity(0.38))
            FlowRow(spacing: pt(10)) {
                ForEach(Array(manifest.items.enumerated()), id: \.element.id) { i, item in
                    VStack(spacing: pt(8)) {
                        ZStack {
                            if let img = media.images[i] { Image(uiImage: img).resizable().scaledToFill() } else { Color(hexString: item.colorHex) }
                        }
                        .frame(width: pt(56), height: pt(56)).clipShape(Circle())
                        .overlay(Circle().strokeBorder(Color(hexString: item.colorHex), lineWidth: pt(2)))
                        Text(item.firstName).font(.custom(PassFont.bodyFamily, fixedSize: pt(12))).foregroundStyle(.white.opacity(0.45))
                    }
                }
            }
            .padding(.horizontal, pt(28))
        }
    }

    private var passed: some View {
        VStack(spacing: pt(8)) {
            Text("\(manifest.passedCount)/\(manifest.participantCount)")
                .font(.custom(PassFont.displayFamily, fixedSize: pt(108)).weight(.black)).tracking(pt(-6)).foregroundStyle(.white)
            Text("PASSED 🔥").font(.custom(PassFont.displayFamily, fixedSize: pt(44)).weight(.black)).tracking(pt(-2)).foregroundStyle(.white)
        }
    }

    private var endCard: some View {
        ZStack {
            LinearGradient(stops: [.init(color: PassColor.violet, location: 0), .init(color: PassColor.violetDeep, location: 0.45), .init(color: PassColor.red, location: 1)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 0) {
                Text("P").font(.custom(PassFont.displayFamily, fixedSize: pt(46)).weight(.black)).foregroundStyle(.white)
                    .frame(width: pt(88), height: pt(88))
                    .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: pt(26), style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: pt(26), style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: pt(1)))
                    .padding(.bottom, pt(24))
                Text("PASS").font(.custom(PassFont.displayFamily, fixedSize: pt(76)).weight(.black)).tracking(pt(-5)).foregroundStyle(.white)
                Rectangle().fill(.white.opacity(0.25)).frame(width: pt(40), height: pt(1)).padding(.vertical, pt(18))
                Text("PASS IT ON.").font(.custom(PassFont.displayFamily, fixedSize: pt(28)).weight(.bold)).tracking(pt(1.1)).foregroundStyle(.white.opacity(0.92))
            }
        }
    }
}

/// Minimal wrapping HStack for the recap avatars (up to 7).
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return CGSize(width: maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var rows: [[(LayoutSubviews.Element, CGSize)]] = [[]]
        var x: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth { rows.append([]); x = 0 }
            rows[rows.count - 1].append((s, size))
            x += size.width + spacing
        }
        var y = bounds.minY
        for row in rows {
            let rowWidth = row.reduce(0) { $0 + $1.1.width } + spacing * CGFloat(max(0, row.count - 1))
            let rowHeight = row.map(\.1.height).max() ?? 0
            var px = bounds.minX + (maxWidth - rowWidth) / 2
            for (s, size) in row {
                s.place(at: CGPoint(x: px, y: y), proposal: ProposedViewSize(size))
                px += size.width + spacing
            }
            y += rowHeight + spacing
        }
    }
}
