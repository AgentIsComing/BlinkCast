import Foundation

#if os(iOS) || os(macOS)
@preconcurrency import AVFoundation
@preconcurrency import WebRTC

final class CameraCaptureService: NSObject, @unchecked Sendable {
    enum CaptureError: LocalizedError {
        case permissionDenied
        case noCamera
        case noFormat
        case startFailed(String)

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Camera permission is required to share camera video."
            case .noCamera:
                return "No camera is available on this device."
            case .noFormat:
                return "The camera has no supported capture format."
            case .startFailed(let message):
                return "Could not start camera capture: \(message)"
            }
        }
    }

    let videoSource: RTCVideoSource
    private let capturer: RTCCameraVideoCapturer
    private(set) var cameraDevice: AVCaptureDevice?

    init(videoSource: RTCVideoSource) {
        self.videoSource = videoSource
        capturer = RTCCameraVideoCapturer(delegate: videoSource)
        super.init()
    }

    func start() async throws {
        let authorization = AVCaptureDevice.authorizationStatus(for: .video)
        if authorization == .notDetermined {
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                throw CaptureError.permissionDenied
            }
        } else if authorization != .authorized {
            throw CaptureError.permissionDenied
        }

        guard let device = preferredDevice() else {
            throw CaptureError.noCamera
        }
        guard let format = preferredFormat(for: device) else {
            throw CaptureError.noFormat
        }

        cameraDevice = device
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            capturer.startCapture(
                with: device,
                format: format,
                fps: 30
            ) { error in
                if let error {
                    continuation.resume(
                        throwing: CaptureError.startFailed(
                            error.localizedDescription
                        )
                    )
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func stop() async {
        await withCheckedContinuation { continuation in
            capturer.stopCapture {
                continuation.resume()
            }
        }
        cameraDevice = nil
    }

    private func preferredDevice() -> AVCaptureDevice? {
        RTCCameraVideoCapturer.captureDevices().first {
            $0.position == .front
        } ?? RTCCameraVideoCapturer.captureDevices().first
    }

    private func preferredFormat(
        for device: AVCaptureDevice
    ) -> AVCaptureDevice.Format? {
        RTCCameraVideoCapturer.supportedFormats(for: device)
            .filter { format in
                let dimensions = CMVideoFormatDescriptionGetDimensions(
                    format.formatDescription
                )
                return dimensions.width >= 640 && dimensions.height >= 480
            }
            .max { lhs, rhs in
                let lhsDimensions = CMVideoFormatDescriptionGetDimensions(
                    lhs.formatDescription
                )
                let rhsDimensions = CMVideoFormatDescriptionGetDimensions(
                    rhs.formatDescription
                )
                return lhsDimensions.width * lhsDimensions.height
                    < rhsDimensions.width * rhsDimensions.height
            }
    }
}
#endif
