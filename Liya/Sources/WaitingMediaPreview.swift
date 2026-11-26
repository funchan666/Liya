import AVFoundation
import SwiftUI
import UIKit

fileprivate struct WaitingCameraSource {
    let session: AVCaptureSession
    let device: AVCaptureDevice
}

@MainActor
final class WaitingMediaCapture: ObservableObject {
    enum State {
        case idle, starting, running, interrupted, unavailable
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var microphoneLevel: Double = 0
    fileprivate private(set) var cameraSource: WaitingCameraSource?
    private var run: WaitingCaptureRun?

    func start(video: Bool) {
        if let run, run.video == video { return }
        stop()
        let requestID = UUID()
        let next = WaitingCaptureRun(id: requestID, video: video) { [weak self] event in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.run?.id == requestID else { return }
                switch event {
                case .running(let source):
                    self.cameraSource = source
                    self.state = .running
                case .interrupted:
                    self.cameraSource = nil
                    self.microphoneLevel = 0
                    self.state = .interrupted
                case .unavailable:
                    self.run = nil
                    self.cameraSource = nil
                    self.microphoneLevel = 0
                    self.state = .unavailable
                case .level(let value):
                    if self.state == .running { self.microphoneLevel = value }
                }
            }
        }
        run = next
        state = .starting
        next.start()
    }

    func stop() {
        run?.stop()
        run = nil
        cameraSource = nil
        microphoneLevel = 0
        state = .idle
    }

    deinit { run?.stop() }
}

private final class WaitingCaptureRun: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    enum Event {
        case running(WaitingCameraSource?), interrupted, unavailable, level(Double)
    }

    let id: UUID
    let video: Bool
    private let notify: (Event) -> Void
    private static let queue = DispatchQueue(label: "liya.waiting.media", qos: .userInitiated)
    private let session = AVCaptureSession()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let stopRequested = NSLock()
    private var cancelled = false
    private var observers: [NSObjectProtocol] = []
    private var camera: AVCaptureDevice?
    private var lastMeterUpdate: TimeInterval = 0
    private var attemptedRecovery = false

    init(id: UUID, video: Bool, notify: @escaping (Event) -> Void) {
        self.id = id
        self.video = video
        self.notify = notify
        super.init()
    }

    func start() {
        Self.queue.async { [self] in
            guard isWanted else { return }
            guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
                  !video || AVCaptureDevice.authorizationStatus(for: .video) == .authorized,
                  configure()
            else { fail(); return }
            guard isWanted else { return }
            observeSession()
            beginCapture()
        }
    }

    func stop() {
        stopRequested.lock()
        let alreadyCancelled = cancelled
        cancelled = true
        stopRequested.unlock()
        if !alreadyCancelled { Self.queue.async { [self] in releaseCapture() } }
    }

    private var isWanted: Bool {
        stopRequested.lock()
        defer { stopRequested.unlock() }
        return !cancelled
    }

    private func configure() -> Bool {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.usesApplicationAudioSession = false
        if video, session.canSetSessionPreset(.medium) { session.sessionPreset = .medium }
        if video {
            guard let front = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
                  addInput(front) else { return false }
            camera = front
        }
        guard let microphone = AVCaptureDevice.default(for: .audio),
              addInput(microphone), session.canAddOutput(audioOutput) else { return false }
        session.addOutput(audioOutput)
        audioOutput.setSampleBufferDelegate(self, queue: Self.queue)
        return true
    }

    private func addInput(_ device: AVCaptureDevice) -> Bool {
        guard let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return false }
        session.addInput(input)
        return true
    }

    private func beginCapture() {
        guard isWanted else { return }
        if !session.isRunning && !session.isInterrupted { session.startRunning() }
        guard isWanted else { return }
        if session.isInterrupted {
            notify(.interrupted)
        } else if session.isRunning {
            notify(.running(camera.map { WaitingCameraSource(session: session, device: $0) }))
        } else {
            fail()
        }
    }

    private func observeSession() {
        for name in [AVCaptureSession.wasInterruptedNotification, AVCaptureSession.interruptionEndedNotification,
                     AVCaptureSession.runtimeErrorNotification] {
            let token = NotificationCenter.default.addObserver(forName: name, object: session, queue: nil) { [weak self] note in
                let code = (note.userInfo?[AVCaptureSessionErrorKey] as? AVError)?.code
                Self.queue.async { [weak self] in
                    guard let self, self.isWanted else { return }
                    switch name {
                    case AVCaptureSession.wasInterruptedNotification:
                        self.notify(.interrupted)
                    case AVCaptureSession.interruptionEndedNotification:
                        self.beginCapture()
                    default:
                        if code == .mediaServicesWereReset && !self.attemptedRecovery {
                            self.attemptedRecovery = true
                            self.beginCapture()
                        } else {
                            self.fail()
                        }
                    }
                }
            }
            observers.append(token)
        }
    }

    private func fail() {
        stop()
        notify(.unavailable)
    }

    private func releaseCapture() {
        for token in observers { NotificationCenter.default.removeObserver(token) }
        observers.removeAll()
        audioOutput.setSampleBufferDelegate(nil, queue: nil)
        session.stopRunning()
        camera = nil
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastMeterUpdate >= 0.12, isWanted, !session.isInterrupted,
              let power = connection.audioChannels.map(\.averagePowerLevel).max() else { return }
        lastMeterUpdate = now
        let level = max(0, min(1, (Double(power) + 60) / 60))
        notify(.level(level))
    }
}

struct WaitingSelfPreview: UIViewRepresentable {
    @ObservedObject var capture: WaitingMediaCapture

    func makeUIView(context: Context) -> PreviewSurface { PreviewSurface() }

    func updateUIView(_ view: PreviewSurface, context: Context) { view.show(capture.cameraSource) }

    static func dismantleUIView(_ view: PreviewSurface, coordinator: ()) { view.show(nil) }

    final class PreviewSurface: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        private var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        private var rotationOwner: AnyObject?
        private var rotationObservation: NSKeyValueObservation?

        fileprivate func show(_ source: WaitingCameraSource?) {
            guard preview.session !== source?.session else { return }
            rotationObservation = nil
            rotationOwner = nil
            preview.videoGravity = .resizeAspectFill
            preview.session = source?.session
            guard let source else { return }
            if let connection = preview.connection, connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
            if #available(iOS 17, *) {
                let owner = AVCaptureDevice.RotationCoordinator(device: source.device, previewLayer: preview)
                rotationOwner = owner
                rotationObservation = owner.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) { [weak self] owner, _ in
                    let angle = owner.videoRotationAngleForHorizonLevelPreview
                    MainActor.assumeIsolated {
                        if let connection = self?.preview.connection, connection.isVideoRotationAngleSupported(angle) {
                            connection.videoRotationAngle = angle
                        }
                    }
                }
            } else {
                updateInterfaceOrientation()
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            if #unavailable(iOS 17) { updateInterfaceOrientation() }
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if #unavailable(iOS 17) { updateInterfaceOrientation() }
        }

        private func updateInterfaceOrientation() {
            guard let orientation = window?.windowScene?.interfaceOrientation,
                  let connection = preview.connection, connection.isVideoOrientationSupported else { return }
            switch orientation {
            case .portrait: connection.videoOrientation = .portrait
            case .portraitUpsideDown: connection.videoOrientation = .portraitUpsideDown
            case .landscapeLeft: connection.videoOrientation = .landscapeLeft
            case .landscapeRight: connection.videoOrientation = .landscapeRight
            default: break
            }
        }
    }
}
