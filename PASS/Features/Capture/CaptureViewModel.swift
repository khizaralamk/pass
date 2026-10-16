import AVFoundation
import Foundation
import Observation
import UIKit

/// Camera → Capture → Preview → Retake / Use This (spec §12). One photo or one video ≤ 4 s. On the simulator (no camera)
/// a placeholder image stands in for the capture so the flow can be exercised end to end.
@MainActor
@Observable
final class CaptureViewModel {
    enum Mode: String, CaseIterable { case photo, video }
    enum Stage: Equatable { case checkingPermission, permissionDenied, camera, preview(CapturedMedia), submitting }

    let relayID: RelayID
    private(set) var stage: Stage = .checkingPermission
    var mode: Mode = .photo
    private(set) var isRecording = false
    private(set) var recordingProgress: Double = 0
    private(set) var isCapturing = false
    var flash = false
    var error: String?
    private(set) var relay: Relay?
    let camera = CameraController()
    let cameraAvailable = CameraController.isAvailable
    private let deps: AppDependencies
    private var recordingTask: Task<Void, Never>?

    init(relayID: RelayID, deps: AppDependencies) {
        self.relayID = relayID
        self.deps = deps
    }

    var maxVideoSeconds: Double { deps.configuration.rules.maxVideoSeconds }
    var challengeTitle: String { relay?.challengeTitle ?? "" }
    var deadline: Date? { relay?.currentTurn?.deadline }

    func start() async {
        relay = try? await deps.relays.relay(relayID)
        guard cameraAvailable else { stage = .camera; return }
        guard await CameraController.requestAccess() else { stage = .permissionDenied; return }
        _ = await CameraController.requestMicrophone() // video audio; photo-only still works if denied
        do {
            try await camera.configure(maxVideoSeconds: maxVideoSeconds)
            camera.start()
            stage = .camera
        } catch {
            self.error = "The camera couldn't start. Please try again."
            stage = .camera
        }
    }

    func stop() {
        recordingTask?.cancel()
        camera.stop()
    }

    func cancel() {
        stop()
        deps.router.fullScreen = nil
    }

    func flip() { guard cameraAvailable else { return }; camera.flip(); Haptics.light() }

    // MARK: Photo

    func capturePhoto() async {
        guard !isCapturing, stage == .camera else { return }
        isCapturing = true
        error = nil
        defer { isCapturing = false }
        do {
            let data: Data
            if cameraAvailable {
                data = try await camera.capturePhoto(flash: flash)
            } else {
                data = try placeholderJPEG()
            }
            guard let image = UIImage(data: data) else { throw CameraController.CameraError.captureFailed }
            let normalized = image.normalizedOrientation().resized(maxDimension: 1920)
            guard let jpeg = normalized.jpegData(compressionQuality: 0.85) else { throw CameraController.CameraError.captureFailed }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("pass-\(UUID().uuidString).jpg")
            try jpeg.write(to: url, options: .atomic)
            Haptics.medium()
            stage = .preview(CapturedMedia(type: .photo, fileURL: url, durationMs: nil))
        } catch {
            self.error = "Couldn't take the photo. Try again."
        }
    }

    // MARK: Video

    func toggleRecording() async {
        if isRecording { await finishRecording() } else { await beginRecording() }
    }

    private func beginRecording() async {
        guard stage == .camera, !isRecording else { return }
        guard cameraAvailable else {
            error = "Video recording needs a real iPhone. Use Photo on the simulator."
            return
        }
        error = nil
        isRecording = true
        recordingProgress = 0
        Haptics.medium()
        camera.startRecordingFresh()
        let started = Date()
        let limit = maxVideoSeconds
        recordingTask = Task { [weak self] in
            // Progress ring; the hard stop is enforced by AVCaptureMovieFileOutput.maxRecordedDuration.
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(started)
                await MainActor.run { self?.recordingProgress = min(1, elapsed / limit) }
                if elapsed >= limit { break }
                try? await Task.sleep(for: .milliseconds(50))
            }
            guard !Task.isCancelled, let self, self.isRecording else { return }
            await self.completeRecording(url: try? await self.camera.awaitRecordingEnd())
        }
    }

    private func finishRecording() async {
        guard isRecording else { return }
        recordingTask?.cancel()
        recordingTask = nil
        let url = try? await camera.stopRecording()
        await completeRecording(url: url)
    }

    private func completeRecording(url: URL?) async {
        isRecording = false
        recordingProgress = 0
        guard let url else { error = "Couldn't save the video. Try again."; return }
        let asset = AVURLAsset(url: url)
        let seconds = (try? await asset.load(.duration).seconds) ?? 0
        guard seconds > 0.3 else { error = "Hold the button a little longer to record."; try? FileManager.default.removeItem(at: url); return }
        Haptics.medium()
        stage = .preview(CapturedMedia(type: .video, fileURL: url, durationMs: Int(min(seconds, maxVideoSeconds) * 1000)))
    }

    // MARK: Preview

    func retake() {
        if case .preview(let media) = stage { try? FileManager.default.removeItem(at: media.fileURL) }
        error = nil
        stage = .camera
        if cameraAvailable { camera.start() }
    }

    /// Submits and locks the contribution (spec §12), then goes to "Who's next?" or Progress if the engine moved on.
    func useThis() async {
        guard case .preview(let media) = stage else { return }
        stage = .submitting
        error = nil
        do {
            let relay = try await deps.relays.submit(relayID: relayID, media: media)
            try? FileManager.default.removeItem(at: media.fileURL)
            Haptics.success()
            stop()
            deps.router.fullScreen = nil
            if let me = deps.session.user?.id, relay.isActive, relay.isHolder(me) {
                deps.router.replaceStack(with: [.passBaton(relayID)])
            } else {
                deps.router.replaceStack(with: [relay.hasReveal ? .relayComplete(relayID) : .progress(relayID)])
            }
        } catch {
            let e = AppError.wrap(error)
            if !e.isCancellation { self.error = e.userMessage }
            stage = .preview(media) // keep the capture so the user can retry without retaking
        }
    }

    // MARK: Simulator placeholder

    private func placeholderJPEG() throws -> Data {
        let size = CGSize(width: 1080, height: 1920)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let colors = [UIColor(red: 0.42, green: 0.27, blue: 1, alpha: 1).cgColor, UIColor.black.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                ctx.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            }
            let style = NSMutableParagraphStyle(); style.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 72, weight: .black), .foregroundColor: UIColor.white, .paragraphStyle: style]
            ("Simulator capture\n\n" + challengeTitle).draw(in: CGRect(x: 60, y: 760, width: 960, height: 500), withAttributes: attrs)
        }
        guard let data = image.jpegData(compressionQuality: 0.85) else { throw CameraController.CameraError.captureFailed }
        return data
    }
}

extension UIImage {
    /// Bakes EXIF orientation into the pixels so every later consumer (Reveal, thumbnails) sees `.up`.
    func normalizedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in draw(in: CGRect(origin: .zero, size: size)) }
    }
}
