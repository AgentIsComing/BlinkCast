import Foundation

#if os(macOS)
@preconcurrency import ScreenCaptureKit
@preconcurrency import WebRTC
import CoreMedia
import CoreVideo

final class ScreenCaptureService: NSObject, @unchecked Sendable {
    struct Quality: Sendable {
        let width: Int
        let height: Int
        let framesPerSecond: Int
    }

    enum Source: String, Sendable {
        case entireScreen
        case monitor
        case window
        case application
    }

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

    func start(source: Source, quality: Quality) async throws {
        let content: SCShareableContent

        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
        } catch {
            throw CaptureError.noPermission
        }

        let filter: SCContentFilter
        let width: Int
        let height: Int

        switch source {
        case .entireScreen, .monitor:
            guard let display = content.displays.first else {
                throw CaptureError.noDisplay
            }
            filter = SCContentFilter(
                display: display,
                excludingApplications: [],
                exceptingWindows: []
            )
            width = display.width
            height = display.height

        case .window:
            guard let window = content.windows.first else {
                throw CaptureError.noDisplay
            }
            filter = SCContentFilter(desktopIndependentWindow: window)
            width = Int(window.frame.width)
            height = Int(window.frame.height)

        case .application:
            guard let application = content.applications.first else {
                throw CaptureError.noDisplay
            }
            guard let window = content.windows.first(where: {
                $0.owningApplication?.processID == application.processID
            }) else {
                throw CaptureError.noDisplay
            }
            filter = SCContentFilter(desktopIndependentWindow: window)
            width = Int(window.frame.width)
            height = Int(window.frame.height)
        }

        let configuration = SCStreamConfiguration()
        configuration.width = min(max(width, 1) * 2, quality.width)
        configuration.height = min(max(height, 1) * 2, quality.height)
        configuration.minimumFrameInterval = CMTime(
            value: 1,
            timescale: CMTimeScale(quality.framesPerSecond)
        )
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
