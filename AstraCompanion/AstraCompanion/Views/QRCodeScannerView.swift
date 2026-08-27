//
//  QRCodeScannerView.swift
//  AstraCompanion
//
//  Created by Alex on 14/8/26.
//

import SwiftUI
import AVFoundation
import UIKit

struct QRCodeScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    let onError: (String) -> Void

    func makeUIViewController(context: Context) -> QRScannerViewController {
        let controller = QRScannerViewController()
        controller.onCode = onCode
        controller.onError = onError
        return controller
    }

    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}
}

final class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    var onError: ((String) -> Void)?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var didFindCode = false

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black
        setupCamera()
        setupOverlay()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                self.session.startRunning()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        if session.isRunning {
            session.stopRunning()
        }
    }

    private func setupCamera() {
        guard let device = AVCaptureDevice.default(for: .video) else {
            onError?("Camera is unavailable.")
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)

            guard session.canAddInput(input) else {
                onError?("Cannot add camera input.")
                return
            }

            session.addInput(input)

            let output = AVCaptureMetadataOutput()

            guard session.canAddOutput(output) else {
                onError?("Cannot add QR output.")
                return
            }

            session.addOutput(output)

            output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            output.metadataObjectTypes = [.qr]

            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.videoGravity = .resizeAspectFill
            preview.frame = view.bounds

            view.layer.insertSublayer(preview, at: 0)
            previewLayer = preview

        } catch {
            onError?("Camera setup error: \(error.localizedDescription)")
        }
    }

    private func setupOverlay() {
        let title = UILabel()
        title.text = "Scan QR code from Astra on Mac"
        title.textColor = .white
        title.font = .systemFont(ofSize: 18, weight: .semibold)
        title.textAlignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false

        let subtitle = UILabel()
        subtitle.text = "Mac Settings → iPhone / iPad Pairing"
        subtitle.textColor = UIColor.white.withAlphaComponent(0.75)
        subtitle.font = .systemFont(ofSize: 13, weight: .regular)
        subtitle.textAlignment = .center
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        let frameView = UIView()
        frameView.layer.borderColor = UIColor.white.withAlphaComponent(0.9).cgColor
        frameView.layer.borderWidth = 3
        frameView.layer.cornerRadius = 22
        frameView.backgroundColor = UIColor.clear
        frameView.translatesAutoresizingMaskIntoConstraints = false

        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
        blur.layer.cornerRadius = 18
        blur.clipsToBounds = true
        blur.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [title, subtitle])
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(blur)
        blur.contentView.addSubview(stack)
        view.addSubview(frameView)

        NSLayoutConstraint.activate([
            blur.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            blur.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            blur.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),

            stack.leadingAnchor.constraint(equalTo: blur.contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: blur.contentView.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: blur.contentView.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: blur.contentView.bottomAnchor, constant: -14),

            frameView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            frameView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            frameView.widthAnchor.constraint(equalToConstant: 260),
            frameView.heightAnchor.constraint(equalToConstant: 260)
        ])
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !didFindCode else { return }

        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              object.type == .qr,
              let value = object.stringValue else {
            return
        }

        didFindCode = true
        session.stopRunning()

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onCode?(value)
    }
}
