import AVFoundation
import Foundation
import Testing
import UIKit
@testable import PASS

/// Builds a real MP4 from fixture photos and checks the container matches spec §23 and the timeline.
struct RevealExporterTests {
    @MainActor
    @Test(.timeLimit(.minutes(8)))
    func exportsPhotoOnlyRevealAt1080x1920WithTimelineDuration() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("reveal-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = LocalMediaStore(directory: dir)
        let members = [MockFixtures.jake, MockFixtures.maya, MockFixtures.zoe]
        var items: [RevealManifest.Item] = []
        for (i, m) in members.enumerated() {
            let file = FixtureMediaFactory.ensurePhoto(for: m, seed: 100 + i, in: store)
            items.append(RevealManifest.Item(position: i + 1, firstName: m.firstName, colorHex: m.colorHex, mediaType: .photo, fileName: file, durationMs: nil))
        }
        let manifest = RevealManifest(relayID: RelayID("test-\(UUID().uuidString)"), challengeTitle: "Worst selfie wins", groupName: "Crew",
                                      outcome: .complete, participantCount: 3, items: items)
        let template = RevealTemplate.standard
        let media = await RevealViewModel.loadMedia(for: manifest, store: store)
        #expect(media.images.count == 3)

        let progress = ProgressBox()
        let url = try await RevealExporter(manifest: manifest, template: template, media: media, store: store).export { p in progress.record(p) }
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(progress.max == 1)

        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let expected = RevealTimeline.totalDuration(RevealTimeline.build(manifest, template: template))
        #expect(abs(duration - expected) < 0.1, "duration \(duration) vs timeline \(expected)")
        let video = try await asset.loadTracks(withMediaType: .video)
        #expect(video.count == 1)
        let size = try await video[0].load(.naturalSize)
        #expect(size == CGSize(width: 1080, height: 1920))
        let audio = try await asset.loadTracks(withMediaType: .audio)
        #expect(audio.count == 1, "silent audio track keeps the container player-friendly")

        let gen = AVAssetImageGenerator(asset: asset)
        gen.requestedTimeToleranceBefore = .zero; gen.requestedTimeToleranceAfter = .zero
        let cg = try await gen.image(at: CMTime(seconds: template.intro + 1.0, preferredTimescale: 600)).image
        #expect(cg.width == 1080 && cg.height == 1920)
    }
}

private final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var max = 0.0
    func record(_ p: Double) { lock.lock(); max = Swift.max(max, p); lock.unlock() }
}
