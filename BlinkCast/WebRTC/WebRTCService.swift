import Foundation
import SwiftUI
import Combine
@preconcurrency import WebRTC

#if os(macOS)
import AppKit
import CoreImage
#else
import UIKit
#endif

@MainActor
final class WebRTCService: NSObject, ObservableObject {
    static let shared = WebRTCService()

    enum State: Equatable {
        case idle
        case preparing
        case negotiating
        case connected
        case failed(String)
    }

    enum Quality: String, CaseIterable, Sendable {
        case balanced
        case high
        case low

        #if os(macOS)
        var captureQuality: ScreenCaptureService.Quality {
            switch self {
            case .balanced:
                return .init(width: 2560, height: 1440, framesPerSecond: 30)
            case .high:
                return .init(width: 3840, height: 2160, framesPerSecond: 60)
            case .low:
                return .init(width: 1280, height: 720, framesPerSecond: 24)
            }
        }
        #endif
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var remoteVideoTrack: RTCVideoTrack?
    @Published private(set) var localVideoTrack: RTCVideoTrack?
    @Published private(set) var localCameraTrack: RTCVideoTrack?
    @Published private(set) var localAudioTrack: RTCAudioTrack?
    @Published private(set) var peerConnectionState = "new"
    @Published private(set) var iceConnectionState = "new"
    @Published private(set) var lastError: String?

    private let signalingService = SignalingService.shared
    private let factory: RTCPeerConnectionFactory
    private var peerConnection: RTCPeerConnection?
    private var pendingRemoteCandidates: [RTCIceCandidate] = []
    private var pendingLocalCandidates: [[String: Any]] = []
    private var remoteClientID: String?
    private var reconnectTask: Task<Void, Never>?
    private var publishMicrophone = false
    private var publishCamera = false
    private var quality: Quality = .balanced
    private var sharingPaused = false
    #if os(iOS) || os(macOS)
    private var cameraCaptureService: CameraCaptureService?
    #endif
    #if os(macOS)
    private var screenCaptureService: ScreenCaptureService?
    private var captureSource: ScreenCaptureService.Source = .entireScreen
    #endif

    private override init() {
        RTCInitializeSSL()
        factory = RTCPeerConnectionFactory(
            encoderFactory: RTCDefaultVideoEncoderFactory(),
            decoderFactory: RTCDefaultVideoDecoderFactory()
        )

        super.init()

        signalingService.onSignal = { [weak self] envelope in
            self?.handleSignal(envelope.data)
        }
    }

    func signalingDidUpdate() {
        switch signalingService.state {
        case .joined:
            switch signalingService.currentRole {
            case .viewer:
                if signalingService.hostAvailable {
                    startViewerIfNeeded()
                }
            case .host:
                startHostingIfNeeded()
            }
        case .waitingForHost:
            break
        case .disconnected:
            stop()
        case .failed(let message):
            fail(message)
        default:
            break
        }
    }

    func startViewerIfNeeded() {
        guard peerConnection == nil,
              signalingService.hostAvailable else {
            return
        }

        state = .preparing

        let configuration = makePeerConnectionConfiguration()

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": UserDefaults.standard.bool(
                    forKey: "blinkcast.receiveAudio"
                ) ? "true" : "false",
                "OfferToReceiveVideo": "true"
            ],
            optionalConstraints: nil
        )

        guard let peerConnection = factory.peerConnection(
            with: configuration,
            constraints: constraints,
            delegate: self
        ) else {
            fail("Could not create WebRTC peer connection.")
            return
        }

        self.peerConnection = peerConnection
        state = .negotiating

        peerConnection.offer(for: constraints) { [weak self] description, error in
            let errorMessage = error?.localizedDescription
            let sdp = description?.sdp
            Task { @MainActor in
                guard let self else { return }

                if let errorMessage {
                    self.fail("Could not create WebRTC offer: \(errorMessage)")
                    return
                }

                guard let sdp else {
                    self.fail("WebRTC did not return an offer.")
                    return
                }

                self.setLocalDescriptionAndSendOffer(sdp: sdp)
            }
        }
    }

    func startHostingIfNeeded() {
        guard signalingService.currentRole == .host,
              peerConnection == nil else {
            return
        }

        #if os(iOS)
        guard publishCamera else {
            fail("iPad can view screen shares. Enable Camera to host camera video.")
            return
        }
        #endif

        state = .preparing

        let configuration = makePeerConnectionConfiguration()
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "false",
                "OfferToReceiveVideo": "false"
            ],
            optionalConstraints: nil
        )

        guard let peerConnection = factory.peerConnection(
            with: configuration,
            constraints: constraints,
            delegate: self
        ) else {
            fail("Could not create the host WebRTC peer connection.")
            return
        }

        self.peerConnection = peerConnection

        #if os(macOS)
        let videoSource = factory.videoSource(forScreenCast: true)
        let videoTrack = factory.videoTrack(
            with: videoSource,
            trackId: "blinkcast-screen"
        )
        _ = peerConnection.add(videoTrack, streamIds: ["blinkcast-stream"])
        screenCaptureService = ScreenCaptureService(videoSource: videoSource)
        localVideoTrack = videoTrack

        if publishMicrophone {
            let audioSource = factory.audioSource(with: nil)
            let audioTrack = factory.audioTrack(
                with: audioSource,
                trackId: "blinkcast-microphone"
            )
            _ = peerConnection.add(
                audioTrack,
                streamIds: ["blinkcast-stream"]
            )
            localAudioTrack = audioTrack
        }

        if publishCamera {
            addCameraTrack(to: peerConnection)
        }

        Task { @MainActor [weak self] in
            do {
                try await self?.screenCaptureService?.start(
                    source: self?.captureSource ?? .entireScreen,
                    quality: self?.quality.captureQuality ?? .init(
                        width: 2560,
                        height: 1440,
                        framesPerSecond: 30
                    )
                )
            } catch {
                self?.fail("Could not start screen capture: \(error.localizedDescription)")
            }
        }
        #endif

        #if os(iOS)
        if publishCamera {
            addCameraTrack(to: peerConnection)
        }
        #endif

        state = .negotiating
    }

    #if os(macOS)
    func setCaptureSource(_ source: ScreenCaptureService.Source) {
        captureSource = source
    }
    #endif

    func setMediaOptions(
        publishMicrophone: Bool,
        publishCamera: Bool = false
    ) {
        self.publishMicrophone = publishMicrophone
        self.publishCamera = publishCamera
    }

    func setQuality(_ quality: Quality) {
        self.quality = quality
    }

    func setSharingPaused(_ paused: Bool) {
        sharingPaused = paused
        localVideoTrack?.isEnabled = !paused
        localAudioTrack?.isEnabled = !paused
    }

    var isSharingPaused: Bool {
        sharingPaused
    }

    func stop() {
        reconnectTask?.cancel()
        reconnectTask = nil
        peerConnection?.close()
        peerConnection = nil
        pendingRemoteCandidates.removeAll()
        pendingLocalCandidates.removeAll()
        remoteClientID = nil
        remoteVideoTrack = nil
        localVideoTrack = nil
        localCameraTrack = nil
        localAudioTrack = nil
        #if os(iOS) || os(macOS)
        let cameraService = cameraCaptureService
        cameraCaptureService = nil
        Task {
            await cameraService?.stop()
        }
        #endif
        peerConnectionState = "closed"
        iceConnectionState = "closed"
        lastError = nil
        #if os(macOS)
        let captureService = screenCaptureService
        screenCaptureService = nil
        Task {
            await captureService?.stop()
        }
        #endif
        state = .idle
    }

    private func scheduleReconnect() {
        guard reconnectTask == nil,
              signalingService.state != .disconnected else {
            return
        }

        state = .negotiating
        reconnectTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return
            }

            guard let self else { return }
            self.reconnectTask = nil
            self.resetPeerConnectionForReconnect()

            switch self.signalingService.currentRole {
            case .viewer:
                self.startViewerIfNeeded()
            case .host:
                self.startHostingIfNeeded()
            }
        }
    }

    private func resetPeerConnectionForReconnect() {
        peerConnection?.close()
        peerConnection = nil
        pendingRemoteCandidates.removeAll()
        pendingLocalCandidates.removeAll()
        remoteClientID = nil
        remoteVideoTrack = nil
        localVideoTrack = nil
        localCameraTrack = nil

        #if os(iOS) || os(macOS)
        let cameraService = cameraCaptureService
        cameraCaptureService = nil
        Task {
            await cameraService?.stop()
        }
        #endif

        #if os(macOS)
        let captureService = screenCaptureService
        screenCaptureService = nil
        Task {
            await captureService?.stop()
        }
        #endif
    }

    #if os(iOS) || os(macOS)
    private func addCameraTrack(to peerConnection: RTCPeerConnection) {
        let videoSource = factory.videoSource()
        let cameraTrack = factory.videoTrack(
            with: videoSource,
            trackId: "blinkcast-camera"
        )
        _ = peerConnection.add(
            cameraTrack,
            streamIds: ["blinkcast-stream"]
        )
        localCameraTrack = cameraTrack

        let cameraService = CameraCaptureService(videoSource: videoSource)
        cameraCaptureService = cameraService
        Task { @MainActor [weak self] in
            do {
                try await cameraService.start()
            } catch {
                self?.fail(error.localizedDescription)
            }
        }
    }
    #endif

    private func makePeerConnectionConfiguration() -> RTCConfiguration {
        let configuration = RTCConfiguration()
        configuration.sdpSemantics = .unifiedPlan
        let configuredURLs = UserDefaults.standard.string(
            forKey: "blinkcast.iceServerURLs"
        )?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []

        if configuredURLs.isEmpty {
            configuration.iceServers = [
                RTCIceServer(urlStrings: [
                    "stun:stun.l.google.com:19302",
                    "stun:stun1.l.google.com:19302"
                ]),
                RTCIceServer(
                    urlStrings: [
                        "turn:openrelay.metered.ca:80",
                        "turn:openrelay.metered.ca:443",
                        "turn:openrelay.metered.ca:443?transport=tcp"
                    ],
                    username: "openrelayproject",
                    credential: "openrelayproject"
                )
            ]
        } else {
            let username = UserDefaults.standard.string(
                forKey: "blinkcast.iceServerUsername"
            ) ?? ""
            let credential = UserDefaults.standard.string(
                forKey: "blinkcast.iceServerCredential"
            ) ?? ""
            configuration.iceServers = [
                RTCIceServer(
                    urlStrings: configuredURLs,
                    username: username,
                    credential: credential
                )
            ]
        }
        return configuration
    }

    private func setLocalDescriptionAndSendOffer(sdp: String) {
        guard let peerConnection else { return }

        let description = RTCSessionDescription(type: .offer, sdp: sdp)
        peerConnection.setLocalDescription(description) { [weak self] error in
            let errorMessage = error?.localizedDescription
            Task { @MainActor in
                guard let self else { return }

                if let errorMessage {
                    self.fail("Could not set local WebRTC description: \(errorMessage)")
                    return
                }

                self.signalingService.sendSignal([
                    "from": self.signalingService.currentClientID,
                    "offer": [
                        "type": "offer",
                        "sdp": description.sdp
                    ]
                ])
            }
        }
    }

    private func handleSignal(_ data: [String: Any]) {
        if let target = data["to"] as? String,
           !target.isEmpty,
           target != signalingService.currentClientID {
            return
        }

        switch signalingService.currentRole {
        case .viewer:
            if let answer = data["answer"] as? [String: Any] {
                handleAnswer(answer)
            }

            if let candidate = data["candidate"] as? [String: Any] {
                handleRemoteCandidate(candidate)
            }

        case .host:
            if let offer = data["offer"] as? [String: Any] {
                handleOffer(offer, from: data["from"] as? String)
            }

            if let candidate = data["candidate"] as? [String: Any] {
                handleRemoteCandidate(candidate)
            }
        }
    }

    private func handleOffer(
        _ payload: [String: Any],
        from clientID: String?
    ) {
        guard let sdp = payload["sdp"] as? String else { return }
        startHostingIfNeeded()
        remoteClientID = clientID
        flushPendingLocalCandidates()

        guard let peerConnection else {
            fail("Host WebRTC connection is not ready for the viewer offer.")
            return
        }

        let description = RTCSessionDescription(type: .offer, sdp: sdp)
        peerConnection.setRemoteDescription(description) { [weak self] error in
            let errorMessage = error?.localizedDescription
            Task { @MainActor in
                guard let self else { return }

                if let errorMessage {
                    self.fail("Could not set the viewer offer: \(errorMessage)")
                    return
                }

                self.createAndSendAnswer()
                self.flushPendingCandidates()
            }
        }
    }

    private func createAndSendAnswer() {
        guard let peerConnection else { return }

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "false",
                "OfferToReceiveVideo": "false"
            ],
            optionalConstraints: nil
        )

        peerConnection.answer(for: constraints) { [weak self] description, error in
            let errorMessage = error?.localizedDescription
            let sdp = description?.sdp
            Task { @MainActor in
                guard let self else { return }

                if let errorMessage {
                    self.fail("Could not create WebRTC answer: \(errorMessage)")
                    return
                }

                guard let sdp else {
                    self.fail("WebRTC did not return an answer.")
                    return
                }

                self.setLocalDescriptionAndSendAnswer(sdp: sdp)
            }
        }
    }

    private func setLocalDescriptionAndSendAnswer(sdp: String) {
        guard let peerConnection else { return }
        let description = RTCSessionDescription(type: .answer, sdp: sdp)

        peerConnection.setLocalDescription(description) { [weak self] error in
            let errorMessage = error?.localizedDescription
            Task { @MainActor in
                guard let self else { return }

                if let errorMessage {
                    self.fail("Could not set local WebRTC answer: \(errorMessage)")
                    return
                }

                var answer: [String: Any] = [
                    "from": self.signalingService.currentClientID,
                    "answer": [
                        "type": "answer",
                        "sdp": sdp
                    ]
                ]

                if let remoteClientID = self.remoteClientID {
                    answer["to"] = remoteClientID
                }

                self.signalingService.sendSignal(answer)
            }
        }
    }

    private func handleAnswer(_ payload: [String: Any]) {
        guard let peerConnection,
              let sdp = payload["sdp"] as? String else {
            return
        }

        let description = RTCSessionDescription(type: .answer, sdp: sdp)

        peerConnection.setRemoteDescription(description) { [weak self] error in
            let errorMessage = error?.localizedDescription
            Task { @MainActor in
                guard let self else { return }

                if let errorMessage {
                    self.fail("Could not set remote WebRTC description: \(errorMessage)")
                    return
                }

                self.flushPendingCandidates()
            }
        }
    }

    private func handleRemoteCandidate(_ payload: [String: Any]) {
        guard let candidateSDP = payload["candidate"] as? String else {
            return
        }

        let sdpMid = payload["sdpMid"] as? String
        let lineIndex: Int32

        if let number = payload["sdpMLineIndex"] as? NSNumber {
            lineIndex = number.int32Value
        } else if let intValue = payload["sdpMLineIndex"] as? Int {
            lineIndex = Int32(intValue)
        } else {
            lineIndex = 0
        }

        let candidate = RTCIceCandidate(
            sdp: candidateSDP,
            sdpMLineIndex: lineIndex,
            sdpMid: sdpMid
        )

        guard let peerConnection else {
            pendingRemoteCandidates.append(candidate)
            return
        }

        if peerConnection.remoteDescription == nil {
            pendingRemoteCandidates.append(candidate)
            return
        }

        peerConnection.add(candidate) { [weak self] error in
            let errorMessage = error?.localizedDescription
            guard let errorMessage else { return }
            Task { @MainActor in
                self?.fail("Could not add ICE candidate: \(errorMessage)")
            }
        }
    }

    private func flushPendingCandidates() {
        guard let peerConnection,
              peerConnection.remoteDescription != nil,
              !pendingRemoteCandidates.isEmpty else {
            return
        }

        let candidates = pendingRemoteCandidates
        pendingRemoteCandidates.removeAll()

        for candidate in candidates {
            peerConnection.add(candidate) { [weak self] error in
                let errorMessage = error?.localizedDescription
                guard let errorMessage else { return }
                Task { @MainActor in
                    self?.fail("Could not add queued ICE candidate: \(errorMessage)")
                }
            }
        }
    }

    private func sendLocalCandidate(
        sdp: String,
        sdpMLineIndex: Int32,
        sdpMid: String?
    ) {
        var candidatePayload: [String: Any] = [
            "candidate": sdp,
            "sdpMLineIndex": Int(sdpMLineIndex)
        ]

        if let sdpMid {
            candidatePayload["sdpMid"] = sdpMid
        }

        var signal: [String: Any] = [
            "from": signalingService.currentClientID,
            "candidate": candidatePayload
        ]

        if let remoteClientID {
            signal["to"] = remoteClientID
        } else if signalingService.currentRole == .host {
            pendingLocalCandidates.append(signal)
            return
        }

        signalingService.sendSignal(signal)
    }

    private func flushPendingLocalCandidates() {
        guard remoteClientID != nil else { return }
        let candidates = pendingLocalCandidates
        pendingLocalCandidates.removeAll()
        for candidate in candidates {
            var targetedCandidate = candidate
            targetedCandidate["to"] = remoteClientID
            signalingService.sendSignal(targetedCandidate)
        }
    }

    private func setRemoteTrack(_ track: RTCMediaStreamTrack?) {
        guard let videoTrack = track as? RTCVideoTrack else { return }
        remoteVideoTrack = videoTrack
    }

    private func fail(_ message: String) {
        lastError = message
        state = .failed(message)
    }
}

extension WebRTCService: RTCPeerConnectionDelegate {
    nonisolated func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didChange stateChanged: RTCSignalingState
    ) {}

    nonisolated func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didAdd stream: RTCMediaStream
    ) {
        let track = stream.videoTracks.first
        Task { @MainActor in self.setRemoteTrack(track) }
    }

    nonisolated func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didRemove stream: RTCMediaStream
    ) {}

    nonisolated func peerConnectionShouldNegotiate(
        _ peerConnection: RTCPeerConnection
    ) {}

    nonisolated func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didChange newState: RTCIceConnectionState
    ) {
        let state = String(describing: newState)
        NSLog("BlinkCast ICE state: \(state)")
        Task { @MainActor in
            self.iceConnectionState = state
        }
    }

    nonisolated func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didChange newState: RTCIceGatheringState
    ) {}

    nonisolated func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didGenerate candidate: RTCIceCandidate
    ) {
        let sdp = candidate.sdp
        let sdpMLineIndex = candidate.sdpMLineIndex
        let sdpMid = candidate.sdpMid
        Task { @MainActor in
            self.sendLocalCandidate(
                sdp: sdp,
                sdpMLineIndex: sdpMLineIndex,
                sdpMid: sdpMid
            )
        }
    }

    nonisolated func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didRemove candidates: [RTCIceCandidate]
    ) {}

    nonisolated func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didOpen dataChannel: RTCDataChannel
    ) {}

    nonisolated func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didChange newState: RTCPeerConnectionState
    ) {
        let state = String(describing: newState)
        NSLog("BlinkCast peer state: \(state)")
        Task { @MainActor in
            self.peerConnectionState = state
            switch newState {
            case .connected:
                self.state = .connected
            case .disconnected:
                self.scheduleReconnect()
            case .failed:
                self.fail("WebRTC connection failed.")
            case .closed:
                if self.state != .idle {
                    self.state = .idle
                }
            default:
                break
            }
        }
    }

    nonisolated func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didStartReceivingOn transceiver: RTCRtpTransceiver
    ) {
        let track = transceiver.receiver.track
        Task { @MainActor in self.setRemoteTrack(track) }
    }

    nonisolated func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didAdd rtpReceiver: RTCRtpReceiver,
        streams: [RTCMediaStream]
    ) {
        let track = rtpReceiver.track
        Task { @MainActor in self.setRemoteTrack(track) }
    }
}

#if os(macOS)
final class BlinkMacRTCVideoView: NSView, RTCVideoRenderer {
    private let ciContext = CIContext(options: nil)
    private nonisolated(unsafe) var didRenderFrame = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.contentsGravity = .resizeAspect
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.contentsGravity = .resizeAspect
    }

    nonisolated func setSize(_ size: CGSize) {}

    nonisolated func renderFrame(_ frame: RTCVideoFrame?) {
        guard let frame,
              let rtcBuffer = frame.buffer as? RTCCVPixelBuffer else {
            return
        }

        let pixelBuffer = rtcBuffer.pixelBuffer
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let rect = CGRect(
            x: 0,
            y: 0,
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )

        guard let cgImage = ciContext.createCGImage(ciImage, from: rect) else {
            return
        }

        if !didRenderFrame {
            didRenderFrame = true
            NSLog("BlinkCast rendered first remote video frame")
        }

        DispatchQueue.main.async { [weak self] in
            self?.layer?.contents = cgImage
        }
    }
}

struct BlinkRemoteVideoView: NSViewRepresentable {
    let track: RTCVideoTrack

    final class Coordinator {
        var attachedTrack: RTCVideoTrack?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> BlinkMacRTCVideoView {
        BlinkMacRTCVideoView(frame: .zero)
    }

    func updateNSView(
        _ view: BlinkMacRTCVideoView,
        context: Context
    ) {
        if context.coordinator.attachedTrack !== track {
            context.coordinator.attachedTrack?.remove(view)
            track.add(view)
            context.coordinator.attachedTrack = track
        }
    }

    static func dismantleNSView(
        _ view: BlinkMacRTCVideoView,
        coordinator: Coordinator
    ) {
        coordinator.attachedTrack?.remove(view)
    }
}
#else
struct BlinkRemoteVideoView: UIViewRepresentable {
    let track: RTCVideoTrack

    final class Coordinator {
        var attachedTrack: RTCVideoTrack?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView(frame: .zero)
        view.videoContentMode = .scaleAspectFit
        return view
    }

    func updateUIView(
        _ view: RTCMTLVideoView,
        context: Context
    ) {
        if context.coordinator.attachedTrack !== track {
            context.coordinator.attachedTrack?.remove(view)
            track.add(view)
            context.coordinator.attachedTrack = track
        }
    }

    static func dismantleUIView(
        _ view: RTCMTLVideoView,
        coordinator: Coordinator
    ) {
        coordinator.attachedTrack?.remove(view)
    }
}
#endif
