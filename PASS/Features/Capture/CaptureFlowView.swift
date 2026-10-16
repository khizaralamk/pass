import SwiftUI
import AVFoundation
import AVKit

/// Full-screen camera + preview (Figma S14, S15).
struct CaptureFlowView: View {
    @State var model: CaptureViewModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch model.stage {
            case .checkingPermission:
                ProgressView().tint(.white)
            case .permissionDenied:
                permissionDenied
            case .camera:
                CameraScreen(model: model)
            case .preview(let media):
                PreviewScreen(model: model, media: media, submitting: false)
            case .submitting:
                if case .preview = model.stage { EmptyView() } else { ProgressView().tint(.white) }
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .task { await model.start() }
        .onDisappear { model.stop() }
    }

    private var permissionDenied: some View {
        VStack(spacing: 16) {
            Text("📷").font(.system(size: 44))
            Text("Camera access is off").outfit(28, .black, tracking: -1).foregroundStyle(.white)
            Text("PASS needs the camera to capture your turn. Turn it on in Settings.").inter(14).foregroundStyle(PassColor.text(0.5)).multilineTextAlignment(.center)
            PassButton(title: "Open Settings", fullWidth: false) {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            PassButton(title: "Not now", variant: .surface, fullWidth: false, action: model.cancel)
        }
        .padding(28)
    }
}

private struct CameraScreen: View {
    @Bindable var model: CaptureViewModel
    @Environment(\.dependencies) private var deps

    var body: some View {
        ZStack {
            if model.cameraAvailable {
                CameraPreview(session: model.camera.session).ignoresSafeArea()
            } else {
                LinearGradient(colors: [Color(hex: 0x1B1033), Color(hex: 0x070707)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                VStack(spacing: 8) {
                    Text("📷").font(.system(size: 40))
                    Text("No camera on the simulator").inter(14).foregroundStyle(PassColor.text(0.5))
                    Text("Photo creates a placeholder capture.").inter(12).foregroundStyle(PassColor.text(0.3))
                }
            }
            LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .center).frame(height: 180).frame(maxHeight: .infinity, alignment: .top).ignoresSafeArea()
            LinearGradient(colors: [.clear, .black.opacity(0.3), .black.opacity(0.88)], startPoint: .top, endPoint: .bottom).frame(height: 240).frame(maxHeight: .infinity, alignment: .bottom).ignoresSafeArea()

            VStack {
                topBar
                Spacer()
                if let e = model.error {
                    Text(e).inter(13).foregroundStyle(.white).padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.black.opacity(0.6), in: Capsule()).padding(.bottom, 12)
                }
                modeToggle.padding(.bottom, 28)
                controls.padding(.bottom, 20)
            }
        }
    }

    private var topBar: some View {
        HStack {
            PhotoPillButton(systemImage: "chevron.left", label: "Back", action: model.cancel)
                .accessibilityIdentifier("capture.back")
            Spacer()
            HStack(spacing: 8) {
                Text(model.challengeTitle).outfit(13, .bold).foregroundStyle(.white).lineLimit(1)
                if let d = model.deadline {
                    Rectangle().fill(.white.opacity(0.2)).frame(width: 1, height: 14)
                    CountdownText(deadline: d, font: PassFont.inter(13, .semibold), color: .white.opacity(0.7))
                }
            }
            .padding(.horizontal, 14).frame(height: 36).frame(maxWidth: 240)
            .background(.black.opacity(0.55), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 1))
            Spacer()
            Color.clear.frame(width: 38, height: 38)
        }
        .padding(.horizontal, 20).padding(.top, 14)
    }

    private var modeToggle: some View {
        HStack(spacing: 0) {
            ForEach(CaptureViewModel.Mode.allCases, id: \.self) { m in
                Button { if !model.isRecording { model.mode = m; Haptics.light() } } label: {
                    Text(m == .photo ? "Photo" : "Video").outfit(14, .bold)
                        .foregroundStyle(model.mode == m ? .black : .white.opacity(0.65))
                        .padding(.horizontal, 22).padding(.vertical, 7)
                        .background(model.mode == m ? Color.white : .clear, in: Capsule())
                }
                .accessibilityAddTraits(model.mode == m ? .isSelected : [])
                .accessibilityIdentifier("capture.mode.\(m.rawValue)")
            }
        }
        .padding(3)
        .background(.black.opacity(0.5), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
        .disabled(model.isRecording)
    }

    private var controls: some View {
        HStack(spacing: 52) {
            Button(action: model.flip) {
                Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 22, weight: .regular)).foregroundStyle(.white.opacity(0.65))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Flip camera")
            .disabled(model.isRecording)

            Button {
                Task {
                    if model.mode == .photo { await model.capturePhoto() } else { await model.toggleRecording() }
                }
            } label: {
                ZStack {
                    Circle().strokeBorder(.white.opacity(0.35), lineWidth: 3).frame(width: 78, height: 78)
                    if model.mode == .video {
                        Circle().trim(from: 0, to: model.recordingProgress).stroke(PassColor.red, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90)).frame(width: 78, height: 78)
                    }
                    Circle().fill(model.mode == .photo ? Color.white : PassColor.red).frame(width: 66, height: 66)
                    if model.mode == .video {
                        RoundedRectangle(cornerRadius: 4).fill(.white).frame(width: model.isRecording ? 26 : 22, height: model.isRecording ? 26 : 22)
                    }
                    if model.isCapturing { ProgressView().tint(.black) }
                }
            }
            .disabled(model.isCapturing)
            .accessibilityLabel(model.mode == .photo ? "Take photo" : model.isRecording ? "Stop recording" : "Record video (up to \(Int(model.maxVideoSeconds)) seconds)")
            .accessibilityIdentifier("capture.shutter")

            Button { model.flash.toggle(); if model.mode == .video { model.camera.setTorch(model.flash) }; Haptics.light() } label: {
                Image(systemName: model.flash ? "bolt.fill" : "bolt").font(.system(size: 22)).foregroundStyle(model.flash ? PassColor.amber : .white.opacity(0.65))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(model.flash ? "Flash on" : "Flash off")
        }
        .padding(.horizontal, 20)
    }
}

private struct PreviewScreen: View {
    @Bindable var model: CaptureViewModel
    let media: CapturedMedia
    let submitting: Bool

    private var isSubmitting: Bool { if case .submitting = model.stage { return true } else { return false } }

    var body: some View {
        ZStack {
            if media.type == .photo, let img = UIImage(contentsOfFile: media.fileURL.path) {
                Image(uiImage: img).resizable().scaledToFill().ignoresSafeArea()
            } else if media.type == .video {
                LoopingVideoView(url: media.fileURL).ignoresSafeArea()
            }
            LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .center).frame(height: 180).frame(maxHeight: .infinity, alignment: .top).ignoresSafeArea()
            LinearGradient(colors: [.clear, .black.opacity(0.3), .black.opacity(0.88)], startPoint: .top, endPoint: .bottom).frame(height: 280).frame(maxHeight: .infinity, alignment: .bottom).ignoresSafeArea()
            VStack {
                HStack { PhotoPillButton(systemImage: "chevron.left", label: "Retake", action: model.retake).disabled(isSubmitting); Spacer() }
                    .padding(.horizontal, 20).padding(.top, 14)
                Spacer()
                VStack(spacing: 14) {
                    if let e = model.error { InlineMessage(text: e).multilineTextAlignment(.center) }
                    Text("Locked until everyone submits · hidden 🔒").inter(14).foregroundStyle(.white.opacity(0.55))
                    HStack(spacing: 12) {
                        PassButton(title: "Retake", variant: .surface, action: model.retake).disabled(isSubmitting)
                            .accessibilityIdentifier("preview.retake")
                        PassButton(title: "Use This ✓", isLoading: isSubmitting) { Task { await model.useThis() } }
                            .accessibilityIdentifier("preview.use")
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 20)
            }
        }
    }
}

/// AVCaptureVideoPreviewLayer host.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

/// Silent-controls looping player for the video preview and the Reveal.
struct LoopingVideoView: UIViewRepresentable {
    let url: URL
    var muted = false

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        var looper: AVPlayerLooper?
        var player: AVQueuePlayer?
    }

    func makeUIView(context: Context) -> PlayerView {
        let v = PlayerView()
        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer()
        v.looper = AVPlayerLooper(player: player, templateItem: item)
        v.player = player
        v.playerLayer.player = player
        v.playerLayer.videoGravity = .resizeAspectFill
        player.isMuted = muted
        player.play()
        return v
    }

    func updateUIView(_ uiView: PlayerView, context: Context) { uiView.player?.isMuted = muted }

    static func dismantleUIView(_ uiView: PlayerView, coordinator: ()) {
        uiView.player?.pause()
        uiView.looper = nil
        uiView.player = nil
    }
}
