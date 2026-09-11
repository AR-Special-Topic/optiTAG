//
//  CameraPreviewView.swift
//  optiTAG
//
//  Created by Paul Weng on 5/8/26.
//

import AVFoundation
import Combine
import SwiftUI

struct CameraPreviewView: View {
    @StateObject private var camera = CameraController()

    var body: some View {
        ZStack {
            CameraPreview(session: camera.session)
                .ignoresSafeArea()

            if let errorMessage = camera.errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)

                    Text(errorMessage)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(hex: "#f8f7ff"))
            }
        }
        .onAppear {
            camera.requestPermissionAndStart()
        }
        .onDisappear {
            camera.stop()
        }
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.videoPreviewLayer.session = session
    }
}

private final class PreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}

final class CameraController: ObservableObject {
    let session = AVCaptureSession()

    @Published var errorMessage: String?

    private let sessionQueue = DispatchQueue(label: "optiTAG.camera.session")
    private var isConfigured = false

    func requestPermissionAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.configureAndStart()
                    } else {
                        self?.errorMessage = "需要允許相機權限才能開始掃描。"
                    }
                }
            }
        case .denied, .restricted:
            errorMessage = "相機權限未開啟，請到系統設定允許 optiTAG 使用相機。"
        @unknown default:
            errorMessage = "無法確認相機權限狀態。"
        }
    }

    func stop() {
        let session = session
        sessionQueue.async {
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    private func configureAndStart() {
        errorMessage = nil

        sessionQueue.async { [weak self] in
            guard let self else { return }

            if !self.isConfigured {
                do {
                    try self.configureSession()
                    self.isConfigured = true
                } catch {
                    DispatchQueue.main.async {
                        self.errorMessage = "相機初始化失敗：\(error.localizedDescription)"
                    }
                    return
                }
            }

            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    private func configureSession() throws {
        session.beginConfiguration()
        session.sessionPreset = .high

        defer {
            session.commitConfiguration()
        }

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CameraError.cameraUnavailable
        }

        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else {
            throw CameraError.inputUnavailable
        }

        session.addInput(input)
    }
}

private enum CameraError: LocalizedError {
    case cameraUnavailable
    case inputUnavailable

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable:
            return "找不到可用的相機。"
        case .inputUnavailable:
            return "無法建立相機輸入。"
        }
    }
}
