import SwiftUI
import AVFoundation

/// Figma "Auto Reveal": full-screen slides with story bars; videos play with their own audio (spec §21). Ends → Post-Reveal.
struct RevealPlayerView: View {
    @State var model: RevealViewModel
    @State private var startDate: Date?
    @State private var finished = false
    @Environment(\.dependencies) private var deps

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch model.phase {
            case .loading:
                LoadingStateView(text: "Building your Reveal…")
            case .failed(let e):
                VStack { PassNavRow(backLabel: "Close", onBack: model.close); ErrorStateView(message: e.userMessage) { Task { await model.load() } } }
            case .noReveal:
                VStack { PassNavRow(backLabel: "Close", onBack: model.close); ErrorStateView(message: "This Relay doesn't have a Reveal.") }
            case .ready:
                player
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .task { await model.load() }
        .onChange(of: model.phase) { _, p in if p == .ready, startDate == nil { startDate = Date() } }
        .onAppear { if model.phase == .ready, startDate == nil { startDate = Date() } }
    }

    private var player: some View {
        GeometryReader { geo in
            TimelineView(.animation) { context in
                let elapsedTotal = startDate.map { context.date.timeIntervalSince($0) } ?? 0
                let segment = RevealTimeline.segment(at: elapsedTotal, in: model.segments) ?? model.segments[0]
                let total = RevealTimeline.totalDuration(model.segments)
                ZStack {
                    if case .participant(let i) = segment.kind, let url = model.media.videoURLs[i] {
                        RevealVideoLayer(url: url, segmentID: segment.id).ignoresSafeArea()
                    }
                    if let manifest = model.manifest {
                        RevealSlideView(manifest: manifest, segment: segment, elapsed: elapsedTotal - segment.start,
                                        media: model.media, canvas: geo.size, template: model.template)
                            .id(segment.id)
                    }
                    storyBars(elapsedTotal: elapsedTotal).frame(maxHeight: .infinity, alignment: .top)
                        .padding(.top, 14).padding(.horizontal, 12)
                    HStack { Spacer(); PhotoPillButton(systemImage: "xmark", label: "Close", action: model.close).accessibilityIdentifier("reveal.close") }
                        .padding(.horizontal, 20).padding(.top, 30).frame(maxHeight: .infinity, alignment: .top)
                }
                .onChange(of: elapsedTotal >= total) { _, done in
                    if done, !finished { finished = true; model.finishedPlaying() }
                }
            }
            .ignoresSafeArea()
        }
        .accessibilityLabel("Reveal playing: \(model.manifest?.challengeTitle ?? "")")
    }

    private func storyBars(elapsedTotal: TimeInterval) -> some View {
        HStack(spacing: 3) {
            ForEach(model.segments) { s in
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.22))
                        Capsule().fill(.white).frame(width: g.size.width * CGFloat(min(1, max(0, (elapsedTotal - s.start) / s.duration))))
                    }
                }
                .frame(height: 3)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Plays one clip once, with its original audio, when its segment begins.
private struct RevealVideoLayer: UIViewRepresentable {
    let url: URL
    let segmentID: RevealSegmentKind

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        var player: AVPlayer?
        var currentURL: URL?
    }

    func makeUIView(context: Context) -> PlayerView {
        let v = PlayerView()
        v.playerLayer.videoGravity = .resizeAspectFill
        load(v)
        return v
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {
        if uiView.currentURL != url { load(uiView) }
    }

    private func load(_ v: PlayerView) {
        let player = AVPlayer(url: url)
        v.player = player
        v.currentURL = url
        v.playerLayer.player = player
        player.play()
    }

    static func dismantleUIView(_ uiView: PlayerView, coordinator: ()) {
        uiView.player?.pause()
        uiView.player = nil
    }
}
