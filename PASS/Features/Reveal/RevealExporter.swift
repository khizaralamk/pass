import AVFoundation
import CoreImage
import Foundation
import SwiftUI
import UIKit

/// Renders the Reveal to an H.264/AAC MP4 at 1080×1920, 30 fps (spec §23) on the device. Every frame is drawn by the
/// same `RevealSlideView` the player shows, so the file matches playback exactly and is deterministic (spec §20).
/// Video clips contribute their own frames and original audio (spec §21); other segments carry silence.
final class RevealExporter: @unchecked Sendable {
    enum ExportError: Error { case writerSetup, frameRender, writerFailed(String), cancelled }

    private let manifest: RevealManifest
    private let template: RevealTemplate
    private let media: RevealMedia
    private let store: any MediaStore
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private let sampleRate: Double = 44_100
    private let channels: UInt32 = 2

    init(manifest: RevealManifest, template: RevealTemplate, media: RevealMedia, store: any MediaStore) {
        self.manifest = manifest
        self.template = template
        self.media = media
        self.store = store
    }

    static func cachedURL(relayID: RelayID, template: RevealTemplate) -> URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = caches.appendingPathComponent("Reveals", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(relayID.raw)-t\(template.version).mp4")
    }

    func export(progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        guard let output = Self.cachedURL(relayID: manifest.relayID, template: template) else { throw ExportError.writerSetup }
        try? FileManager.default.removeItem(at: output)
        let segments = RevealTimeline.build(manifest, template: template)
        let total = RevealTimeline.totalDuration(segments)
        let fps = template.fps
        let size = CGSize(width: template.width, height: template.height)

        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: template.width,
            AVVideoHeightKey: template.height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 9_000_000, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel],
        ])
        videoInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: template.width,
            kCVPixelBufferHeightKey as String: template.height,
        ])
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: 128_000,
        ])
        audioInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput), writer.canAdd(audioInput) else { throw ExportError.writerSetup }
        writer.add(videoInput)
        writer.add(audioInput)
        guard writer.startWriting() else { throw ExportError.writerFailed(writer.error?.localizedDescription ?? "start") }
        writer.startSession(atSourceTime: .zero)

        let startedAt = Date()
        let totalFrames = Int((total * Double(fps)).rounded(.up))
        var framesDone = 0
        do {
            for segment in segments {
                try Task.checkCancellation()
                let firstFrame = Int((segment.start * Double(fps)).rounded(.up))
                let lastFrame = min(totalFrames, Int((segment.end * Double(fps)).rounded(.up)))
                var clipFrames: ClipFrameSource?
                var clipAudio: ClipAudioSource?
                if case .participant(let i) = segment.kind, let url = media.videoURLs[i] {
                    clipFrames = try? await ClipFrameSource(url: url, ciContext: ciContext)
                    clipAudio = try? await ClipAudioSource(url: url, sampleRate: sampleRate, channels: channels)
                }
                var lastImage: CGImage?
                var lastKey: Int = -1
                for frame in firstFrame..<lastFrame {
                    try Task.checkCancellation()
                    let time = Double(frame) / Double(fps)
                    let elapsed = time - segment.start
                    let clipImage = clipFrames?.frame(at: elapsed)
                    // Frames are identical once the fade and the name animation have settled: reuse the last render.
                    let settled = elapsed >= max(template.fade, template.nameDelay + template.nameDuration) + 0.05
                        && (segment.duration <= 2.0 || elapsed < template.nameFadeOutAt || elapsed > template.nameFadeOutAt + 0.35)
                    let key = (clipImage == nil && settled) ? (elapsed < template.nameFadeOutAt ? 1 : 2) : frame
                    let image: CGImage
                    if key == lastKey, let lastImage {
                        image = lastImage
                    } else {
                        image = try await renderFrame(segment: segment, elapsed: elapsed, size: size, clipImage: clipImage)
                        lastImage = image
                        lastKey = key
                    }
                    // Keep audio slightly ahead of video; AVAssetWriter stops accepting a track that runs far ahead of the other.
                    try await fillAudio(upTo: time + 0.5, segment: segment, clip: clipAudio, input: audioInput, writer: writer)
                    try await append(image, to: adaptor, input: videoInput, writer: writer, time: CMTime(value: CMTimeValue(frame), timescale: fps))
                    framesDone += 1
                    if framesDone % 5 == 0 { progress(Double(framesDone) / Double(max(1, totalFrames))) }
                }
                try await fillAudio(upTo: segment.end, segment: segment, clip: clipAudio, input: audioInput, writer: writer)
                RevealExporter.log("segment \(segment.kind) done at \(Date().timeIntervalSince(startedAt).rounded())s")
            }
        } catch {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: output)
            throw error is CancellationError ? ExportError.cancelled : error
        }
        videoInput.markAsFinished()
        audioInput.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: output)
            throw ExportError.writerFailed(writer.error?.localizedDescription ?? "unknown")
        }
        progress(1)
        return output
    }

    // MARK: Video frames

    @MainActor
    private func renderFrame(segment: RevealSegment, elapsed: TimeInterval, size: CGSize, clipImage: UIImage?) async throws -> CGImage {
        let view = RevealSlideView(manifest: manifest, segment: segment, elapsed: elapsed, media: media, canvas: size, template: template, videoFrame: clipImage)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(size)
        guard let cg = renderer.cgImage else { throw ExportError.frameRender }
        await Task.yield() // keep the UI responsive between frames
        return cg
    }

    private func append(_ image: CGImage, to adaptor: AVAssetWriterInputPixelBufferAdaptor, input: AVAssetWriterInput, writer: AVAssetWriter, time: CMTime) async throws {
        try await waitUntilReady(input, writer: writer)
        guard let pool = adaptor.pixelBufferPool else { throw ExportError.writerSetup }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let pixelBuffer = buffer else { throw ExportError.writerSetup }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pixelBuffer), width: image.width, height: image.height, bitsPerComponent: 8,
                                  bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer), space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else {
            throw ExportError.frameRender
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard adaptor.append(pixelBuffer, withPresentationTime: time) else { throw ExportError.writerFailed("video append: \(writer.error?.localizedDescription ?? "")") }
    }

    // MARK: Audio

    /// Audio cursor in sample frames at `sampleRate`, shared across segments so the track is continuous.
    private var audioFrames: Int64 = 0

    /// Appends clip audio (when the segment has a clip) or silence until the audio track reaches `seconds`, capped at the
    /// segment end. Called before every video frame and once at each segment end.
    private func fillAudio(upTo seconds: Double, segment: RevealSegment, clip: ClipAudioSource?, input: AVAssetWriterInput, writer: AVAssetWriter) async throws {
        let rate = Int32(sampleRate)
        let segmentEnd = Int64((segment.end * sampleRate).rounded())
        let target = min(Int64((seconds * sampleRate).rounded()), segmentEnd)
        while audioFrames < target {
            try Task.checkCancellation()
            let pts = CMTime(value: audioFrames, timescale: rate)
            if let clip, let sample = clip.next() {
                let count = Int64(CMSampleBufferGetNumSamples(sample))
                let take = min(count, segmentEnd - audioFrames)
                if take > 0, let retimed = retime(sample, to: pts, frames: take) { try await append(retimed, to: input, writer: writer) }
                audioFrames += max(take, 1)
            } else {
                let n = min(4096, segmentEnd - audioFrames)
                if let silence = makeSilence(frames: Int(n), at: pts) { try await append(silence, to: input, writer: writer) }
                audioFrames += n
            }
        }
    }

    private func append(_ sample: CMSampleBuffer, to input: AVAssetWriterInput, writer: AVAssetWriter) async throws {
        try await waitUntilReady(input, writer: writer)
        guard input.append(sample) else { throw ExportError.writerFailed("audio append: \(writer.error?.localizedDescription ?? "")") }
    }

    /// Waits for the input, but never forever: a failed writer reports its error instead of stalling the export.
    private func waitUntilReady(_ input: AVAssetWriterInput, writer: AVAssetWriter) async throws {
        var waited = 0
        while !input.isReadyForMoreMediaData {
            try Task.checkCancellation()
            if writer.status == .failed { throw ExportError.writerFailed(writer.error?.localizedDescription ?? "writer failed") }
            if waited > 2000 { throw ExportError.writerFailed("writer not accepting data") } // 10 s
            waited += 1
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    static func log(_ message: @autoclosure () -> String) {
        #if DEBUG
        print("[RevealExporter] \(message())")
        #endif
    }

    private var asbd: AudioStreamBasicDescription {
        AudioStreamBasicDescription(mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
                                    mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
                                    mBytesPerPacket: 2 * channels, mFramesPerPacket: 1, mBytesPerFrame: 2 * channels,
                                    mChannelsPerFrame: channels, mBitsPerChannel: 16, mReserved: 0)
    }

    private func makeSilence(frames: Int, at time: CMTime) -> CMSampleBuffer? {
        var desc = asbd
        var format: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(allocator: nil, asbd: &desc, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil,
                                             extensions: nil, formatDescriptionOut: &format) == noErr, let format else { return nil }
        let bytes = frames * Int(desc.mBytesPerFrame)
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: bytes, blockAllocator: nil, customBlockSource: nil,
                                                 offsetToData: 0, dataLength: bytes, flags: 0, blockBufferOut: &block) == noErr, let block else { return nil }
        CMBlockBufferFillDataBytes(with: 0, blockBuffer: block, offsetIntoDestination: 0, dataLength: bytes)
        var sample: CMSampleBuffer?
        guard CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: frames,
                                                                   presentationTimeStamp: time, packetDescriptions: nil, sampleBufferOut: &sample) == noErr else { return nil }
        return sample
    }

    private func retime(_ sample: CMSampleBuffer, to time: CMTime, frames: Int64) -> CMSampleBuffer? {
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: Int32(sampleRate)), presentationTimeStamp: time, decodeTimeStamp: .invalid)
        var out: CMSampleBuffer?
        guard CMSampleBufferCreateCopyWithNewTiming(allocator: nil, sampleBuffer: sample, sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleBufferOut: &out) == noErr,
              let out else { return nil }
        let count = Int64(CMSampleBufferGetNumSamples(out))
        if frames < count, let trimmed = try? out.copy(trimmedTo: Int(frames)) { return trimmed }
        return out
    }
}

/// Sequential frames of one clip as oriented UIImages (reads in order; one frame in memory at a time).
private final class ClipFrameSource {
    private let reader: AVAssetReader
    private let output: AVAssetReaderTrackOutput
    private let ciContext: CIContext
    private let orientation: UIImage.Orientation
    private var pending: (time: Double, image: UIImage)?
    private var finished = false

    init(url: URL, ciContext: CIContext) async throws {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw RevealExporter.ExportError.frameRender }
        let transform = try await track.load(.preferredTransform)
        orientation = Self.orientation(for: transform)
        reader = try AVAssetReader(asset: asset)
        output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        reader.startReading()
        self.ciContext = ciContext
    }

    /// The clip frame at or just before `time` (seconds from clip start). Holds the last frame once the clip ends.
    func frame(at time: Double) -> UIImage? {
        while !finished, pending == nil || pending!.time < time {
            guard let sample = output.copyNextSampleBuffer(), let pb = CMSampleBufferGetImageBuffer(sample) else { finished = true; break }
            let t = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            if let next = pending, next.time <= time, t > time { break } // keep the previous frame; this one is still ahead
            if let cg = ciContext.createCGImage(CIImage(cvPixelBuffer: pb), from: CIImage(cvPixelBuffer: pb).extent) {
                pending = (t, UIImage(cgImage: cg, scale: 1, orientation: orientation))
            }
            if t >= time { break }
        }
        return pending?.image
    }

    private static func orientation(for t: CGAffineTransform) -> UIImage.Orientation {
        if t.a == 0 && t.b == 1 && t.c == -1 && t.d == 0 { return .right }
        if t.a == 0 && t.b == -1 && t.c == 1 && t.d == 0 { return .left }
        if t.a == -1 && t.d == -1 { return .down }
        if t.a == 0 && t.b == 1 && t.c == 1 && t.d == 0 { return .rightMirrored }
        if t.a == 0 && t.b == -1 && t.c == -1 && t.d == 0 { return .leftMirrored }
        return .up
    }
}

/// Decoded LPCM samples of a clip's audio track, matching the writer's format. `nil` when the clip has no audio.
private final class ClipAudioSource {
    private let reader: AVAssetReader
    private let output: AVAssetReaderTrackOutput

    init?(url: URL, sampleRate: Double, channels: UInt32) async throws {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return nil }
        reader = try AVAssetReader(asset: asset)
        output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
        ])
        reader.add(output)
        reader.startReading()
    }

    func next() -> CMSampleBuffer? { output.copyNextSampleBuffer() }
}

private extension CMSampleBuffer {
    /// Keeps the first `frames` samples of an LPCM buffer.
    func copy(trimmedTo frames: Int) throws -> CMSampleBuffer {
        try CMSampleBuffer(copying: self, forRange: 0..<frames)
    }
}
