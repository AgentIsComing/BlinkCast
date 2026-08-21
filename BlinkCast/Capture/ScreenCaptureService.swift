import Foundation

#if os(iOS)
import CoreMedia
import CoreVideo
import ReplayKit
@preconcurrency import WebRTC

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
        case unavailable
        case permissionDenied
        case startFailed(String)

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "Screen recording is not available on this device."
            case .permissionDenied:
                return "Screen Recording permission is required to share this screen."
            case .startFailed(let message):
                return "Could not start screen capture: \(message)"
            }
        }
    }

    nonisolated(unsafe) let videoSource: RTCVideoSource
    private nonisolated(unsafe) let videoCapturer: RTCVideoCapturer

    init(videoSource: RTCVideoSource) {
        self.videoSource = videoSource
        videoCapturer = RTCVideoCapturer(delegate: videoSource)
        super.init()
    }

    nonisolated func start(source: Source, quality: Quality) {
        guard RPScreenRecorder.shared().isAvailable else {
            NSLog("BlinkCast ReplayKit unavailable on this device")
            return
        }

        let recorder = RPScreenRecorder.shared()
        if recorder.isRecording {
            return
        }

        recorder.startCapture(handler: { [weak self] sampleBuffer, sampleType, error in
            guard let self else { return }

            if let error {
                NSLog("BlinkCast ReplayKit capture error: \(error.localizedDescription)")
                return
            }

            guard sampleType == .video else {
                return
            }

            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                return
            }

            let timestamp = Int64(
                CMTimeGetSeconds(sampleBuffer.presentationTimeStamp) * 1_000_000_000
            )
            let frame = RTCVideoFrame(
                buffer: RTCCVPixelBuffer(pixelBuffer: pixelBuffer),
                rotation: ._0,
                timeStampNs: timestamp
            )

            RTCDispatcher.dispatchAsync(on: .typeCaptureSession) { [weak self] in
                guard let self else { return }
                self.videoSource.capturer(self.videoCapturer, didCapture: frame)
            }
        }, completionHandler: { error in
            if let error {
                NSLog("BlinkCast ReplayKit start failed: \(error.localizedDescription)")
                return
            }
        })
    }

    nonisolated func stop() async {
        guard RPScreenRecorder.shared().isRecording else { return }
        await withCheckedContinuation { continuation in
            RPScreenRecorder.shared().stopCapture(handler: { _ in
                continuation.resume()
            })
        }
    }
}
#endif

#if os(macOS)
@preconcurrency import ScreenCaptureKit
@preconcurrency import WebRTC
import CoreGraphics
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
        case queryFailed(String)

        var errorDescription: String? {
            switch self {
            case .noDisplay:
                return "No display is available for screen capture."
            case .noPermission:
                return "Screen Recording permission is required to share this screen."
            case .queryFailed(let message):
                return "Could not query available screens: \(message)"
            }
        }
    }

    nonisolated(unsafe) let videoSource: RTCVideoSource
    private nonisolated(unsafe) let videoCapturer: RTCVideoCapturer
    private let outputQueue = DispatchQueue(label: "com.blinkcast.screen-capture")
    private var stream: SCStream?
    private nonisolated(unsafe) var frameCount = 0

    init(videoSource: RTCVideoSource) {
        self.videoSource = videoSource
        videoCapturer = RTCVideoCapturer(delegate: videoSource)
        super.init()
    }

    func start(source: Source, quality: Quality) async throws {
        if !CGPreflightScreenCaptureAccess() {
            NSLog("BlinkCast macOS screen recording preflight returned false; requesting access")
            let granted = CGRequestScreenCaptureAccess()
            if !granted {
                throw CaptureError.noPermission
            }
            NSLog("BlinkCast macOS screen recording request returned granted")
            restoreAppWindow()
        }

        let content: SCShareableContent

        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
        } catch {
            NSLog("BlinkCast macOS ScreenCaptureKit content query failed: \(error.localizedDescription)")
            throw CaptureError.queryFailed(error.localizedDescription)
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
        restoreAppWindow()
        self.stream = stream
    }

    private func restoreAppWindow() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.windows.first {
                if window.isMiniaturized {
                    window.deminiaturize(nil)
                }
                window.orderFrontRegardless()
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    func stop() async {
        guard let stream else { return }
        self.stream = nil
        try? await stream.stopCapture()
    }
}

extension ScreenCaptureService: SCStreamOutput, SCStreamDelegate {
    nonisolated func stream(
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
        if frameCount == 0 || frameCount % 60 == 0 {
            NSLog("BlinkCast macOS screen capture frame count=\(frameCount) size=\(CVPixelBufferGetWidth(pixelBuffer))x\(CVPixelBufferGetHeight(pixelBuffer))")
        }
        frameCount += 1
        videoSource.capturer(videoCapturer, didCapture: frame)
    }

    nonisolated func stream(
        _ stream: SCStream,
        didStopWithError error: Error
    ) {
        NSLog("BlinkCast screen capture stopped: \(error.localizedDescription)")
    }
}
#endif
