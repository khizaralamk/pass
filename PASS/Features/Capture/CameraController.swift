import AVFoundation
import UIKit

/// AVFoundation session for one photo or one ≤ 4-second video (spec §12). All session work happens on a private queue;
/// results are delivered through async functions. The controller owns nothing UI-related except the preview layer.
final class CameraController: NSObject, @unchecked Sendable {
    enum CameraError: Error { case unavailable, permissionDenied, configuration, captureFailed }

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "pass.camera", qos: .userInitiated)
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private(set) var position: AVCaptureDevice.Position = .back
    private var photoContinuation: CheckedContinuation<Data, Error>?
    private var movieContinuation: CheckedContinuation<URL, Error>?
    /// Set when a recording finished (e.g. by the duration limit) before anyone awaited it.
    private var finishedRecording: Result<URL, Error>?
    private var configured = false

    static var isAvailable: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
            || AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil
    }

    static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    static func requestMicrophone() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    func configure(maxVideoSeconds: Double) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    guard !self.configured else { c.resume(); return }
                    self.session.beginConfiguration()
                    self.session.sessionPreset = .high
                    try self.attachCamera(position: .back)
                    if let mic = AVCaptureDevice.default(for: .audio), let input = try? AVCaptureDeviceInput(device: mic), self.session.canAddInput(input) {
                        self.session.addInput(input)
                        self.audioInput = input
                    }
                    guard self.session.canAddOutput(self.photoOutput), self.session.canAddOutput(self.movieOutput) else {
                        self.session.commitConfiguration()
                        throw CameraError.configuration
                    }
                    self.session.addOutput(self.photoOutput)
                    self.session.addOutput(self.movieOutput)
                    self.movieOutput.maxRecordedDuration = CMTime(seconds: maxVideoSeconds, preferredTimescale: 600)
                    self.session.commitConfiguration()
                    self.configured = true
                    c.resume()
                } catch {
                    c.resume(throwing: error)
                }
            }
        }
    }

    private func attachCamera(position: AVCaptureDevice.Position) throws {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else { throw CameraError.unavailable }
        let input = try AVCaptureDeviceInput(device: device)
        if let old = videoInput { session.removeInput(old) }
        guard session.canAddInput(input) else { throw CameraError.configuration }
        session.addInput(input)
        videoInput = input
        self.position = position
        if let connection = movieOutput.connection(with: .video), connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = position == .front
        }
    }

    func start() { queue.async { if !self.session.isRunning { self.session.startRunning() } } }
    func stop() { queue.async { if self.session.isRunning { self.session.stopRunning() } } }

    func flip() {
        queue.async {
            self.session.beginConfiguration()
            try? self.attachCamera(position: self.position == .back ? .front : .back)
            self.session.commitConfiguration()
        }
    }

    func setTorch(_ on: Bool) {
        queue.async {
            guard let device = self.videoInput?.device, device.hasTorch else { return }
            try? device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        }
    }

    var hasTorch: Bool { videoInput?.device.hasTorch ?? false }

    func capturePhoto(flash: Bool) async throws -> Data {
        try await withCheckedThrowingContinuation { c in
            queue.async {
                guard self.photoContinuation == nil else { c.resume(throwing: CameraError.captureFailed); return }
                self.photoContinuation = c
                let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
                settings.flashMode = flash && self.photoOutput.supportedFlashModes.contains(.on) ? .on : .off
                self.photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    func startRecording() {
        queue.async {
            guard !self.movieOutput.isRecording else { return }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("pass-\(UUID().uuidString).mov")
            if let connection = self.movieOutput.connection(with: .video) {
                connection.videoRotationAngle = 90 // portrait
            }
            self.movieOutput.startRecording(to: url, recordingDelegate: self)
        }
    }

    /// Resolves when the file is finalised, whether stopped by the user or by the 4-second limit.
    func stopRecording() async throws -> URL {
        try await withCheckedThrowingContinuation { c in
            queue.async {
                if let done = self.finishedRecording { self.finishedRecording = nil; c.resume(with: done); return }
                guard self.movieContinuation == nil else { c.resume(throwing: CameraError.captureFailed); return }
                self.movieContinuation = c
                if self.movieOutput.isRecording { self.movieOutput.stopRecording() }
            }
        }
    }

    /// Waits for a recording that the duration limit will end on its own.
    func awaitRecordingEnd() async throws -> URL {
        try await withCheckedThrowingContinuation { c in
            queue.async {
                if let done = self.finishedRecording { self.finishedRecording = nil; c.resume(with: done); return }
                guard self.movieContinuation == nil else { c.resume(throwing: CameraError.captureFailed); return }
                self.movieContinuation = c
            }
        }
    }

    func startRecordingFresh() { queue.async { self.finishedRecording = nil }; startRecording() }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        queue.async {
            let c = self.photoContinuation
            self.photoContinuation = nil
            if let error { c?.resume(throwing: error); return }
            guard let data = photo.fileDataRepresentation() else { c?.resume(throwing: CameraError.captureFailed); return }
            c?.resume(returning: data)
        }
    }
}

extension CameraController: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        queue.async {
            let c = self.movieContinuation
            self.movieContinuation = nil
            // Hitting maxRecordedDuration reports an error with the file still valid; treat that as success.
            let result: Result<URL, Error>
            if let error, (error as NSError).userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool != true {
                result = .failure(error)
            } else {
                result = .success(outputFileURL)
            }
            if let c { c.resume(with: result) } else { self.finishedRecording = result }
        }
    }
}
