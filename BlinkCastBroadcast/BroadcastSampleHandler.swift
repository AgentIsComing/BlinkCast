import ReplayKit

final class BroadcastSampleHandler: RPBroadcastSampleHandler {
    private var session: BroadcastWebRTCSession?
    private var videoSampleCount = 0
    private var ignoredSampleCount = 0

    override init() {
        super.init()
        blinkExtensionLog("BlinkCast EXTENSION init bundle=\(Bundle.main.bundleIdentifier ?? "unknown") principal=\(String(describing: type(of: self)))")
    }

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        blinkExtensionLog("BlinkCast EXTENSION broadcastStarted setupInfoPresent=\(setupInfo != nil) setupKeys=\(setupInfo?.keys.sorted() ?? [])")
        blinkExtensionLog("BlinkCast EXTENSION process=\(ProcessInfo.processInfo.processName) pid=\(ProcessInfo.processInfo.processIdentifier)")
        let session = BroadcastWebRTCSession()
        self.session = session
        session.start()
    }

    override func processSampleBuffer(
        _ sampleBuffer: CMSampleBuffer,
        with sampleBufferType: RPSampleBufferType
    ) {
        guard sampleBufferType == .video else {
            ignoredSampleCount += 1
            if ignoredSampleCount <= 3 || ignoredSampleCount % 60 == 0 {
                blinkExtensionLog("BlinkCast EXTENSION ignored non-video sample type=\(sampleBufferType.rawValue) count=\(ignoredSampleCount)")
            }
            return
        }
        videoSampleCount += 1
        if videoSampleCount <= 3 || videoSampleCount % 60 == 0 {
            blinkExtensionLog("BlinkCast EXTENSION video sample count=\(videoSampleCount) valid=\(CMSampleBufferIsValid(sampleBuffer))")
        }
        session?.capture(sampleBuffer)
    }

    override func broadcastFinished() {
        blinkExtensionLog("BlinkCast EXTENSION broadcastFinished videoSamples=\(videoSampleCount) sessionPresent=\(session != nil)")
        session?.stop()
        session = nil
    }
}
