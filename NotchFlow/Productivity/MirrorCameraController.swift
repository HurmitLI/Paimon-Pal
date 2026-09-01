import AppKit
import AVFoundation
import SwiftUI

@MainActor
final class MirrorCameraController: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var statusText = "摄像头默认关闭。"

    let session = AVCaptureSession()
    private var input: AVCaptureDeviceInput?

    func start() {
        guard !isRunning else { return }
        Task { @MainActor in
            let allowed = await AVCaptureDevice.requestAccess(for: .video)
            guard allowed else {
                statusText = "摄像头权限未开启，可到系统设置的“隐私与安全性 → 摄像头”中调整。"
                return
            }
            configureAndStart()
        }
    }

    func stop() {
        guard isRunning || session.isRunning else { return }
        session.stopRunning()
        isRunning = false
        statusText = "摄像头已关闭。"
    }

    private func configureAndStart() {
        do {
            session.beginConfiguration()
            session.sessionPreset = .high
            if input == nil {
                guard let camera = AVCaptureDevice.default(for: .video) else {
                    session.commitConfiguration()
                    statusText = "没有找到可用的摄像头。"
                    return
                }
                let input = try AVCaptureDeviceInput(device: camera)
                guard session.canAddInput(input) else {
                    session.commitConfiguration()
                    statusText = "摄像头无法加入预览会话。"
                    return
                }
                session.addInput(input)
                self.input = input
            }
            session.commitConfiguration()
            session.startRunning()
            isRunning = session.isRunning
            statusText = isRunning ? "镜子已开启；离开页面会自动关闭。" : "镜子未能启动。"
        } catch {
            session.commitConfiguration()
            statusText = "无法启动摄像头：\(error.localizedDescription)"
        }
    }
}

final class MirrorPreviewView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override func makeBackingLayer() -> CALayer {
        AVCaptureVideoPreviewLayer()
    }

    var previewLayer: AVCaptureVideoPreviewLayer? {
        layer as? AVCaptureVideoPreviewLayer
    }
}

struct MirrorSessionView: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> MirrorPreviewView {
        let view = MirrorPreviewView()
        view.previewLayer?.session = session
        view.previewLayer?.videoGravity = .resizeAspectFill
        view.previewLayer?.cornerRadius = 18
        view.previewLayer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: MirrorPreviewView, context: Context) {
        nsView.previewLayer?.session = session
    }
}
