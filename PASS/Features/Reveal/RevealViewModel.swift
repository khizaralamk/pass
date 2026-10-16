import AVFoundation
import Foundation
import Observation
import Photos
import UIKit

/// Loads a finished relay, decodes its media, drives playback and owns the export (Share / Save).
@MainActor
@Observable
final class RevealViewModel {
    enum Phase: Equatable { case loading, failed(AppError), ready, noReveal }

    let relayID: RelayID
    private(set) var phase: Phase = .loading
    private(set) var relay: Relay?
    private(set) var manifest: RevealManifest?
    private(set) var segments: [RevealSegment] = []
    private(set) var media = RevealMedia()
    private(set) var exportProgress: Double?
    private(set) var exportedURL: URL?
    var exportError: String?
    var saveMessage: String?
    let template = RevealTemplate.standard
    private let deps: AppDependencies
    private var exportTask: Task<URL, Error>?

    init(relayID: RelayID, deps: AppDependencies) {
        self.relayID = relayID
        self.deps = deps
    }

    var isExporting: Bool { exportProgress != nil }
    var mediaStore: any MediaStore { deps.media }

    func load() async {
        guard phase != .ready else { return }
        phase = .loading
        do {
            let r = try await deps.relays.relay(relayID)
            relay = r
            guard let m = try await deps.revealManifests.manifest(for: r) else { phase = .noReveal; return }
            manifest = m
            segments = RevealTimeline.build(m, template: template)
            media = await Self.loadMedia(for: m, store: deps.media)
            if let cached = RevealExporter.cachedURL(relayID: relayID, template: template), FileManager.default.fileExists(atPath: cached.path) {
                exportedURL = cached
            }
            phase = .ready
        } catch {
            let e = AppError.wrap(error)
            if !e.isCancellation { phase = .failed(e) }
        }
    }

    /// Decodes photos (downscaled to the canvas) and grabs a poster frame for each video, off the main actor.
    nonisolated static func loadMedia(for manifest: RevealManifest, store: any MediaStore) async -> RevealMedia {
        await Task.detached(priority: .userInitiated) { () -> RevealMedia in
            var media = RevealMedia()
            for (i, item) in manifest.items.enumerated() {
                let url = store.url(for: item.fileName)
                switch item.mediaType {
                case .photo:
                    if let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
                        media.images[i] = img.resized(maxDimension: 1920).preparingForDisplay() ?? img
                    }
                case .video:
                    media.videoURLs[i] = url
                    let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
                    gen.appliesPreferredTrackTransform = true
                    gen.maximumSize = CGSize(width: 1080, height: 1920)
                    if let cg = try? await gen.image(at: .zero).image { media.images[i] = UIImage(cgImage: cg) }
                }
            }
            return media
        }.value
    }

    func finishedPlaying() {
        deps.router.fullScreen = nil
        deps.router.replaceStack(with: [.postReveal(relayID)])
    }

    func close() { deps.router.fullScreen = nil }
    func watchAgain() { deps.router.fullScreen = .reveal(relayID) }
    func goHome() { deps.router.popToRoot() }
    func startAnother() { guard let r = relay else { return }; deps.router.replaceStack(with: [.newRelayChallenge(r.groupID)]) }

    // MARK: Export (spec §23: MP4, 9:16, 1080×1920)

    /// Builds (or reuses) the MP4. Concurrent callers share one export task.
    func exportIfNeeded() async throws -> URL {
        if let url = exportedURL, FileManager.default.fileExists(atPath: url.path) { return url }
        if let task = exportTask { return try await task.value }
        guard let manifest else { throw AppError.media("This Relay has no Reveal.") }
        let template = self.template
        let media = self.media
        let store = deps.media
        exportProgress = 0
        exportError = nil
        let task = Task<URL, Error> { [weak self] in
            let exporter = RevealExporter(manifest: manifest, template: template, media: media, store: store)
            return try await exporter.export { progress in
                Task { @MainActor [weak self] in self?.exportProgress = progress }
            }
        }
        exportTask = task
        defer { exportTask = nil; exportProgress = nil }
        do {
            let url = try await task.value
            exportedURL = url
            return url
        } catch {
            let e = AppError.wrap(error)
            if !e.isCancellation { exportError = e.userMessage }
            throw e
        }
    }

    func cancelExport() { exportTask?.cancel() }

    /// Saves to Photos with add-only permission (spec §23).
    func saveToPhotos() async {
        saveMessage = nil
        do {
            let url = try await exportIfNeeded()
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                exportError = "Allow PASS to add to your Photos in Settings to save the Reveal."
                return
            }
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
            Haptics.success()
            saveMessage = "Saved to Photos ✓"
        } catch {
            let e = AppError.wrap(error)
            if !e.isCancellation { exportError = e.userMessage }
        }
    }

    func reportRelay(reason: ReportReason, details: String) async -> Bool {
        do { try await deps.users.report(target: .relay(relayID), reason: reason, details: details); deps.router.showToast("Report sent. Thank you."); return true }
        catch { return false }
    }
}
