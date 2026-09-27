import SwiftUI
import AVFoundation
import Vision
import UIKit
import ImageIO

/// v0.9 책 전용 커스텀 카메라.
/// 화면 안에서 페이지 외곽을 추적하고, 일정 시간 안정된 상태 + 최소 품질 점수를 만족하면 자동 촬영합니다.
/// 같은 페이지가 그대로 유지되면 이미지 유사도로 재촬영을 억제합니다.
struct BookAutoCameraView: UIViewControllerRepresentable {
    let captureMode: ScanProfile.CaptureMode
    let autoCaptureEnabled: Bool
    let minimumQualityScore: Int
    let autoCaptureDelay: Double
    var onFinish: ([UIImage]) -> Void
    var onCancel: () -> Void
    var onError: (Error) -> Void

    func makeUIViewController(context: Context) -> BookAutoCameraViewController {
        BookAutoCameraViewController(
            captureMode: captureMode,
            autoCaptureEnabled: autoCaptureEnabled,
            minimumQualityScore: minimumQualityScore,
            autoCaptureDelay: autoCaptureDelay,
            onFinish: onFinish,
            onCancel: onCancel,
            onError: onError
        )
    }

    func updateUIViewController(_ uiViewController: BookAutoCameraViewController, context: Context) {}
}

final class BookAutoCameraViewController: UIViewController, AVCapturePhotoCaptureDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let captureMode: ScanProfile.CaptureMode
    private var autoCaptureEnabled: Bool
    private let minimumQualityScore: Int
    private let autoCaptureDelay: Double
    private let onFinish: ([UIImage]) -> Void
    private let onCancel: () -> Void
    private let onError: (Error) -> Void

    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let analysisQueue = DispatchQueue(label: "BookScannerReader.camera.analysis", qos: .userInitiated)
    private let sessionQueue = DispatchQueue(label: "BookScannerReader.camera.session", qos: .userInitiated)
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private let processor = ScanProcessingService()

    private var previewLayer: AVCaptureVideoPreviewLayer!
    private let pageLayer = CAShapeLayer()
    private let guideLayer = CAShapeLayer()
    private let statusLabel = UILabel()
    private let countLabel = UILabel()
    private let hintLabel = UILabel()
    private let shutterButton = UIButton(type: .system)
    private let autoButton = UIButton(type: .system)
    private let torchButton = UIButton(type: .system)
    private let doneButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)

    private var configured = false
    private var camera: AVCaptureDevice?
    private var capturedImages: [UIImage] = []
    private var lastCapturedImage: UIImage?
    private var lastObservationBox: CGRect?
    private var stableSince: Date?
    private var lastAnalysisDate = Date.distantPast
    private var lastCaptureDate = Date.distantPast
    private var isCapturing = false
    private var latestQualityScore = 0
    private var latestDuplicateScore = 0.0
    private var manualCaptureRequested = false

    init(
        captureMode: ScanProfile.CaptureMode,
        autoCaptureEnabled: Bool,
        minimumQualityScore: Int,
        autoCaptureDelay: Double,
        onFinish: @escaping ([UIImage]) -> Void,
        onCancel: @escaping () -> Void,
        onError: @escaping (Error) -> Void
    ) {
        self.captureMode = captureMode
        self.autoCaptureEnabled = autoCaptureEnabled
        self.minimumQualityScore = min(max(minimumQualityScore, 40), 95)
        self.autoCaptureDelay = min(max(autoCaptureDelay, 0.4), 2.0)
        self.onFinish = onFinish
        self.onCancel = onCancel
        self.onError = onError
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureInterface()
        requestCameraAndConfigure()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        sessionQueue.async { [weak self] in
            guard let self, self.configured, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        guideLayer.frame = view.bounds
        pageLayer.frame = view.bounds
        updateGuidePath()
    }

    private func configureInterface() {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)

        guideLayer.fillColor = UIColor.clear.cgColor
        guideLayer.strokeColor = UIColor.white.withAlphaComponent(0.40).cgColor
        guideLayer.lineWidth = 2
        guideLayer.lineDashPattern = [8, 6]
        view.layer.addSublayer(guideLayer)

        pageLayer.fillColor = UIColor.systemGreen.withAlphaComponent(0.08).cgColor
        pageLayer.strokeColor = UIColor.systemGreen.cgColor
        pageLayer.lineWidth = 3
        pageLayer.shadowColor = UIColor.black.cgColor
        pageLayer.shadowOpacity = 0.25
        pageLayer.shadowRadius = 3
        view.layer.addSublayer(pageLayer)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textColor = .white
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 2
        statusLabel.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        statusLabel.layer.cornerRadius = 12
        statusLabel.clipsToBounds = true
        statusLabel.text = "카메라 준비 중…"

        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.textColor = .white
        countLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        countLabel.textAlignment = .center
        countLabel.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        countLabel.layer.cornerRadius = 10
        countLabel.clipsToBounds = true
        countLabel.text = "촬영 0장"

        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.textColor = UIColor.white.withAlphaComponent(0.85)
        hintLabel.font = .preferredFont(forTextStyle: .footnote)
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 2
        hintLabel.text = captureMode == .doublePage
            ? "펼친 두 페이지 전체가 안내선 안에 들어오게 맞추세요."
            : "한 페이지 전체가 안내선 안에 들어오게 맞추세요."

        configureButton(cancelButton, title: "취소", systemImage: "xmark", action: #selector(cancelTapped))
        configureButton(doneButton, title: "완료", systemImage: "checkmark", action: #selector(doneTapped))
        configureButton(autoButton, title: autoCaptureEnabled ? "자동 ON" : "자동 OFF", systemImage: "viewfinder", action: #selector(autoTapped))
        configureButton(torchButton, title: "조명", systemImage: "flashlight.off.fill", action: #selector(torchTapped))

        shutterButton.translatesAutoresizingMaskIntoConstraints = false
        shutterButton.tintColor = .white
        shutterButton.backgroundColor = UIColor.white.withAlphaComponent(0.18)
        shutterButton.layer.cornerRadius = 36
        shutterButton.layer.borderColor = UIColor.white.cgColor
        shutterButton.layer.borderWidth = 4
        shutterButton.addTarget(self, action: #selector(shutterTapped), for: .touchUpInside)
        let shutterImage = UIImage(systemName: "camera.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 28, weight: .semibold))
        shutterButton.setImage(shutterImage, for: .normal)

        let topBar = UIStackView(arrangedSubviews: [cancelButton, UIView(), countLabel, UIView(), doneButton])
        topBar.translatesAutoresizingMaskIntoConstraints = false
        topBar.axis = .horizontal
        topBar.alignment = .center
        topBar.spacing = 10

        let bottomBar = UIStackView(arrangedSubviews: [torchButton, autoButton, shutterButton])
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.axis = .horizontal
        bottomBar.alignment = .center
        bottomBar.distribution = .equalCentering
        bottomBar.spacing = 20

        [topBar, statusLabel, hintLabel, bottomBar].forEach(view.addSubview)

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),

            countLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 86),
            countLabel.heightAnchor.constraint(equalToConstant: 36),

            statusLabel.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 12),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.88),
            statusLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),

            hintLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            hintLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            hintLabel.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -16),

            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            bottomBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -18),
            bottomBar.heightAnchor.constraint(equalToConstant: 76),

            shutterButton.widthAnchor.constraint(equalToConstant: 72),
            shutterButton.heightAnchor.constraint(equalToConstant: 72)
        ])
    }

    private func configureButton(_ button: UIButton, title: String, systemImage: String, action: Selector) {
        button.translatesAutoresizingMaskIntoConstraints = false
        var config = UIButton.Configuration.filled()
        config.title = title
        config.image = UIImage(systemName: systemImage)
        config.imagePadding = 5
        config.baseBackgroundColor = UIColor.black.withAlphaComponent(0.55)
        config.baseForegroundColor = .white
        config.cornerStyle = .capsule
        button.configuration = config
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private func updateGuidePath() {
        let safe = view.safeAreaInsets
        let top = max(safe.top + 92, 130)
        let bottom = max(safe.bottom + 126, 150)
        let horizontal: CGFloat = captureMode == .doublePage ? 16 : 42
        let rect = CGRect(
            x: horizontal,
            y: top,
            width: max(view.bounds.width - horizontal * 2, 40),
            height: max(view.bounds.height - top - bottom, 80)
        )
        guideLayer.path = UIBezierPath(roundedRect: rect, cornerRadius: 18).cgPath
    }

    private func requestCameraAndConfigure() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                if granted {
                    self.configureSession()
                } else {
                    self.reportCameraPermissionError()
                }
            }
        default:
            reportCameraPermissionError()
        }
    }

    private func reportCameraPermissionError() {
        let error = NSError(
            domain: "BookScannerReader.Camera",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "카메라 권한이 필요합니다. 설정 → 개인정보 보호 및 보안 → 카메라에서 Book Scanner 권한을 허용해주세요."]
        )
        DispatchQueue.main.async { [weak self] in
            self?.onError(error)
        }
    }

    private func configureSession() {
        sessionQueue.async { [weak self] in
            guard let self, !self.configured else { return }

            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                self.session.commitConfiguration()
                self.reportConfigurationError("후면 카메라를 찾을 수 없습니다.")
                return
            }
            self.camera = device

            do {
                let input = try AVCaptureDeviceInput(device: device)
                guard self.session.canAddInput(input) else {
                    self.session.commitConfiguration()
                    self.reportConfigurationError("카메라 입력을 연결할 수 없습니다.")
                    return
                }
                self.session.addInput(input)
            } catch {
                self.session.commitConfiguration()
                DispatchQueue.main.async { self.onError(error) }
                return
            }

            guard self.session.canAddOutput(self.photoOutput), self.session.canAddOutput(self.videoOutput) else {
                self.session.commitConfiguration()
                self.reportConfigurationError("카메라 출력을 연결할 수 없습니다.")
                return
            }

            self.session.addOutput(self.photoOutput)
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            self.videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
            ]
            self.videoOutput.setSampleBufferDelegate(self, queue: self.analysisQueue)
            self.session.addOutput(self.videoOutput)

            if let connection = self.videoOutput.connection(with: .video), connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            if let connection = self.photoOutput.connection(with: .video), connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }

            do {
                try device.lockForConfiguration()
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                device.unlockForConfiguration()
            } catch {
                // 초점/노출 설정 실패는 촬영 자체를 막지 않습니다.
            }

            self.session.commitConfiguration()
            self.configured = true
            self.session.startRunning()

            DispatchQueue.main.async {
                self.statusLabel.text = self.autoCaptureEnabled ? "페이지를 안내선에 맞춰주세요" : "수동 촬영 모드"
            }
        }
    }

    private func reportConfigurationError(_ message: String) {
        let error = NSError(
            domain: "BookScannerReader.Camera",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
        DispatchQueue.main.async { [weak self] in self?.onError(error) }
    }

    @objc private func cancelTapped() {
        stopSession()
        onCancel()
    }

    @objc private func doneTapped() {
        stopSession()
        onFinish(capturedImages)
    }

    @objc private func shutterTapped() {
        manualCaptureRequested = true
        capturePhoto()
    }

    @objc private func autoTapped() {
        autoCaptureEnabled.toggle()
        stableSince = nil
        var config = autoButton.configuration
        config?.title = autoCaptureEnabled ? "자동 ON" : "자동 OFF"
        config?.image = UIImage(systemName: autoCaptureEnabled ? "viewfinder" : "viewfinder.circle")
        autoButton.configuration = config
        statusLabel.text = autoCaptureEnabled ? "페이지를 안내선에 맞춰주세요" : "수동 촬영 모드"
    }

    @objc private func torchTapped() {
        guard let camera, camera.hasTorch else { return }
        do {
            try camera.lockForConfiguration()
            if camera.torchMode == .on {
                camera.torchMode = .off
            } else if camera.isTorchModeSupported(.on) {
                try camera.setTorchModeOn(level: 0.35)
            }
            let isOn = camera.torchMode == .on
            camera.unlockForConfiguration()

            var config = torchButton.configuration
            config?.image = UIImage(systemName: isOn ? "flashlight.on.fill" : "flashlight.off.fill")
            config?.title = isOn ? "조명 ON" : "조명"
            torchButton.configuration = config
        } catch {
            // 손전등 전환 실패는 무시합니다.
        }
    }

    private func stopSession() {
        if let camera, camera.hasTorch, camera.torchMode == .on {
            do {
                try camera.lockForConfiguration()
                camera.torchMode = .off
                camera.unlockForConfiguration()
            } catch {
                // 종료 중 손전등 해제 실패는 무시합니다.
            }
        }
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    private func capturePhoto() {
        guard !isCapturing, configured else { return }
        isCapturing = true
        lastCaptureDate = .now
        let settings = AVCapturePhotoSettings()
        settings.photoQualityPrioritization = .quality
        if let connection = photoOutput.connection(with: .video), connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
        photoOutput.capturePhoto(with: settings, delegate: self)

        DispatchQueue.main.async { [weak self] in
            self?.statusLabel.text = "촬영 중…"
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            isCapturing = false
            manualCaptureRequested = false
            DispatchQueue.main.async { [weak self] in self?.onError(error) }
            return
        }

        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            isCapturing = false
            manualCaptureRequested = false
            return
        }

        capturedImages.append(image)
        lastCapturedImage = image
        isCapturing = false
        manualCaptureRequested = false
        stableSince = nil
        lastObservationBox = nil
        latestDuplicateScore = 1

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.countLabel.text = "촬영 \(self.capturedImages.count)장"
            self.statusLabel.text = self.autoCaptureEnabled ? "저장됨 · 페이지를 넘겨주세요" : "저장됨"
            self.flashCaptureFeedback()
        }
    }

    private func flashCaptureFeedback() {
        let flash = UIView(frame: view.bounds)
        flash.backgroundColor = UIColor.white.withAlphaComponent(0.70)
        flash.isUserInteractionEnabled = false
        view.addSubview(flash)
        UIView.animate(withDuration: 0.16, animations: {
            flash.alpha = 0
        }, completion: { _ in
            flash.removeFromSuperview()
        })
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = Date()
        guard now.timeIntervalSince(lastAnalysisDate) >= 0.18, !isCapturing else { return }
        lastAnalysisDate = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 5
        request.minimumConfidence = 0.35
        request.minimumSize = captureMode == .doublePage ? 0.22 : 0.28
        request.minimumAspectRatio = captureMode == .doublePage ? 0.20 : 0.30
        request.maximumAspectRatio = 1.0
        request.quadratureTolerance = 38

        do {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
            try handler.perform([request])
        } catch {
            return
        }

        guard let candidates = request.results, let observation = candidates.max(by: {
            ($0.boundingBox.width * $0.boundingBox.height * CGFloat($0.confidence)) <
            ($1.boundingBox.width * $1.boundingBox.height * CGFloat($1.confidence))
        }) else {
            resetStability(status: autoCaptureEnabled ? "페이지 전체를 화면에 보여주세요" : "수동 촬영 모드", color: .systemYellow)
            updatePageOverlay(nil, color: .systemYellow)
            return
        }

        let box = observation.boundingBox
        let area = Double(box.width * box.height)
        let minimumArea = captureMode == .doublePage ? 0.24 : 0.30
        guard area >= minimumArea else {
            resetStability(status: "조금 더 가까이 촬영해주세요", color: .systemYellow)
            updatePageOverlay(box, color: .systemYellow)
            return
        }

        let movement = lastObservationBox.map { normalizedRectDistance($0, box) } ?? 1
        lastObservationBox = box

        let previewImage = makePreviewImage(pixelBuffer)
        let qualityScore = previewImage.map { processor.qualityReport($0).score } ?? 0
        latestQualityScore = qualityScore

        var duplicateScore = 0.0
        if let previewImage, let lastCapturedImage {
            duplicateScore = processor.imageSimilarity(previewImage, lastCapturedImage)
        }
        latestDuplicateScore = duplicateScore

        if duplicateScore >= 0.982, now.timeIntervalSince(lastCaptureDate) > 0.75 {
            stableSince = nil
            updatePageOverlay(box, color: .systemOrange)
            updateStatus("같은 페이지로 보여요 · 다음 페이지를 넘겨주세요", color: .systemOrange)
            return
        }

        let stableThreshold = 0.018
        if movement <= stableThreshold {
            if stableSince == nil { stableSince = now }
        } else {
            stableSince = nil
        }

        guard autoCaptureEnabled else {
            updatePageOverlay(box, color: .systemGreen)
            updateStatus("수동 촬영 · 품질 \(qualityScore)점", color: .systemGreen)
            return
        }

        guard qualityScore >= minimumQualityScore else {
            stableSince = nil
            updatePageOverlay(box, color: .systemYellow)
            updateStatus("품질 \(qualityScore)점 · 초점과 조명을 확인하세요", color: .systemYellow)
            return
        }

        guard let stableSince else {
            updatePageOverlay(box, color: .systemYellow)
            updateStatus("카메라를 잠시 고정해주세요 · 품질 \(qualityScore)점", color: .systemYellow)
            return
        }

        let held = now.timeIntervalSince(stableSince)
        let progress = min(max(held / autoCaptureDelay, 0), 1)
        if progress < 1 {
            updatePageOverlay(box, color: .systemGreen)
            updateStatus("자동 촬영 준비 \(Int((progress * 100).rounded()))% · 품질 \(qualityScore)점", color: .systemGreen)
            return
        }

        guard now.timeIntervalSince(lastCaptureDate) >= 1.1 else { return }
        self.stableSince = nil
        DispatchQueue.main.async { [weak self] in
            self?.capturePhoto()
        }
    }

    private func makePreviewImage(_ pixelBuffer: CVPixelBuffer) -> UIImage? {
        let input = CIImage(cvPixelBuffer: pixelBuffer)
        let extent = input.extent
        let maxDimension: CGFloat = 720
        let scale = min(1, maxDimension / max(extent.width, extent.height))
        let resized = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = ciContext.createCGImage(resized, from: resized.extent) else { return nil }
        return UIImage(cgImage: cg, scale: 1, orientation: .right)
    }

    private func normalizedRectDistance(_ lhs: CGRect, _ rhs: CGRect) -> Double {
        let center = hypot(Double(lhs.midX - rhs.midX), Double(lhs.midY - rhs.midY))
        let size = hypot(Double(lhs.width - rhs.width), Double(lhs.height - rhs.height))
        return center + size * 0.7
    }

    private func resetStability(status: String, color: UIColor) {
        stableSince = nil
        lastObservationBox = nil
        updateStatus(status, color: color)
    }

    private func updateStatus(_ text: String, color: UIColor) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.statusLabel.text = text
            self.statusLabel.layer.borderWidth = 1
            self.statusLabel.layer.borderColor = color.withAlphaComponent(0.8).cgColor
        }
    }

    private func updatePageOverlay(_ visionBox: CGRect?, color: UIColor) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pageLayer.strokeColor = color.cgColor
            self.pageLayer.fillColor = color.withAlphaComponent(0.08).cgColor
            guard let visionBox else {
                self.pageLayer.path = nil
                return
            }

            // Vision은 좌하단 원점, metadata rect는 좌상단 원점을 사용합니다.
            let metadataRect = CGRect(
                x: visionBox.minX,
                y: 1 - visionBox.maxY,
                width: visionBox.width,
                height: visionBox.height
            )
            let rect = self.previewLayer.layerRectConverted(fromMetadataOutputRect: metadataRect)
            self.pageLayer.path = UIBezierPath(roundedRect: rect, cornerRadius: 12).cgPath
        }
    }
}
