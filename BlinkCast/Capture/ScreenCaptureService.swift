import Foundation

#if os(macOS)
@preconcurrency import ScreenCaptureKit
@preconcurrency import WebRTC
import CoreMedia
import CoreVideo

final class ScreenCaptureService: NSObject, @unchecked Sendable {
    enum CaptureError: LocalizedError {
        case noDisplay
        case noPermission

        var errorDescription: String? {
            switch self {
            case .noDisplay:
                return "No display is available for screen capture."
            case .noPermission:
                return "Screen Recording permission is required to share this screen."
            }
        }
    }

    let videoSource: RTCVideoSource
    private let videoCapturer: RTCVideoCapturer
    private let outputQueue = DispatchQueue(label: "com.blinkcast.screen-capture")
    private var stream: SCStream?

    init(videoSource: RTCVideoSource) {
        self.videoSource = videoSource
        videoCapturer = RTCVideoCapturer(delegate: videoSource)
        super.init()
    }

    func start() async throws {
        let content: SCShareableContent

        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
        } catch {
            throw CaptureError.noPermission
        }

        guard let display = content.displays.first else {
            throw CaptureError.noDisplay
        }

        let filter = SCContentFilter(
            display: display,
            excludingApplications: [],
            exceptingWindows: []
        )
        let configuration = SCStreamConfiguration()
        configuration.width = min(display.width * 2, 3840)
        configuration.height = min(display.height * 2, 2160)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 3
        configuration.pixelFormat = kCVPixelFormatType_32BGRA

        let stream = SCStream(
            filter: filter,
            configuration: configuration,
            delegate: self
        )
        try stream.addStreamOutput(
            self,
            type: .screen,
            sampleHandlerQueue: outputQueue
        )
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async {
        guard let stream else { return }
        self.stream = nil
        try? await stream.stopCapture()
    }
}

extension ScreenCaptureService: SCStreamOutput, SCStreamDelegate {
    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen,
              let pixelBuffer = sampleBuffer.imageBuffer else {
            return
        }

        let buffer = RTCCVPixelBuffer(pixelBuffer: pixelBuffer)
        let timestamp = Int64(
            CMTimeGetSeconds(sampleBuffer.presentationTimeStamp) * 1_000_000_000
        )
        let frame = RTCVideoFrame(
            buffer: buffer,
            rotation: ._0,
            timeStampNs: timestamp
        )
        videoSource.capturer(videoCapturer, didCapture: frame)
    }

    func stream(
        _ stream: SCStream,
        didStopWithError error: Error
    ) {
        NSLog("BlinkCast screen capture stopped: \(error.localizedDescription)")
    }
}
#endif
