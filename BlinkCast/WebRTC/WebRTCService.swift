import Foundation
import SwiftUI
@preconcurrency import WebRTC

#if os(macOS)
import AppKit
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

    @Published private(set) var state: State = .idle
    @Published private(set) var remoteVideoTrack: RTCVideoTrack?

    private let signalingService = SignalingService.shared

    private let factory: RTCPeerConnectionFactory
    private var peerConnection: RTCPeerConnection?
    private var pendingRemoteCandidates: [RTCIceCandidate] = []

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
        guard signalingService.currentRole == .viewer else {
            return
        }

        switch signalingService.state {
        case .joined:
            if signalingService.hostAvailable {
                startViewerIfNeeded()
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
        guard peerConnection == nil else {
            return
        }

        guard signalingService.hostAvailable else {
            return
        }

        state = .preparing

        let configuration = RTCConfiguration()
        configuration.sdpSemantics = .unifiedPlan
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

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "true",
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
            Task { @MainActor in
                guard let self else {
                    return
                }

                if let error {
                    self.fail("Could not create WebRTC offer: \(error.localizedDescription)")
                    return
                }

                guard let description else {
                    self.fail("WebRTC did not return an offer.")
                    return
                }

                self.setLocalDescriptionAndSendOffer(description)
            }
        }
    }

    func stop() {
        peerConnection?.close()
        peerConnection = nil
        pendingRemoteCandidates.removeAll()
        remoteVideoTrack = nil
        state = .idle
    }

    private func setLocalDescriptionAndSendOffer(
        _ description: RTCSessionDescription
    ) {
        guard let peerConnection else {
            return
        }

        peerConnection.setLocalDescription(description) { [weak self] error in
            Task { @MainActor in
                guard let self else {
                    return
                }

                if let error {
                    self.fail("Could not set local WebRTC description: \(error.localizedDescription)")
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
        guard signalingService.currentRole == .viewer else {
            return
        }

        if let target = data["to"] as? String,
           !target.isEmpty,
           target != signalingService.currentClientID {
            return
        }

        if let answer = data["answer"] as? [String: Any] {
            handleAnswer(answer)
        }

        if let candidate = data["candidate"] as? [String: Any] {
            handleRemoteCandidate(candidate)
        }
    }

    private func handleAnswer(_ payload: [String: Any]) {
        guard
            let peerConnection,
            let sdp = payload["sdp"] as? String
        else {
            return
        }

        let description = RTCSessionDescription(
            type: .answer,
            sdp: sdp
        )

        peerConnection.setRemoteDescription(description) { [weak self] error in
            Task { @MainActor in
                guard let self else {
                    return
                }

                if let error {
                    self.fail("Could not set remote WebRTC description: \(error.localizedDescription)")
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
            guard let error else {
                return
            }

            Task { @MainActor in
                self?.fail("Could not add ICE candidate: \(error.localizedDescription)")
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
                guard let error else {
                    return
                }

                Task { @MainActor in
                    self?.fail("Could not add queued ICE candidate: \(error.localizedDescription)")
                }
            }
        }
    }

    private func sendLocalCandidate(_ candidate: RTCIceCandidate) {
        var candidatePayload: [String: Any] = [
            "candidate": candidate.sdp,
            "sdpMLineIndex": Int(candidate.sdpMLineIndex)
        ]

        if let sdpMid = candidate.sdpMid {
            candidatePayload["sdpMid"] = sdpMid
        }

        signalingService.sendSignal([
            "from": signalingService.currentClientID,
            "candidate": candidatePayload
        ])
    }

    private func setRemoteTrack(_ track: RTCMediaStreamTrack?) {
        guard let videoTrack = track as? RTCVideoTrack else {
            return
        }

        remoteVideoTrack = videoTrack
    }

    private func fail(_ message: String) {
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
        Task { @MainActor in
            self.setRemoteTrack(track)
        }
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
    ) {}

    nonisolated func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didChange newState: RTCIceGatheringState
    ) {}

    nonisolated func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didGenerate candidate: RTCIceCandidate
    ) {
        Task { @MainActor in
            self.sendLocalCandidate(candidate)
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
        Task { @MainActor in
            switch newState {
            case .connected:
                self.state = .connected

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
        Task { @MainActor in
            self.setRemoteTrack(track)
        }
    }

    nonisolated func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didAdd rtpReceiver: RTCRtpReceiver,
        streams: [RTCMediaStream]
    ) {
        let track = rtpReceiver.track
        Task { @MainActor in
            self.setRemoteTrack(track)
        }
    }
}

#if os(macOS)
struct BlinkRemoteVideoView: NSViewRepresentable {
    let track: RTCVideoTrack

    final class Coordinator {
        var attachedTrack: RTCVideoTrack?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView(frame: .zero)
        view.videoContentMode = .scaleAspectFit
        return view
    }

    func updateNSView(
        _ view: RTCMTLVideoView,
        context: Context
    ) {
        if context.coordinator.attachedTrack !== track {
            context.coordinator.attachedTrack?.remove(view)
            track.add(view)
            context.coordinator.attachedTrack = track
        }
    }

    static func dismantleNSView(
        _ view: RTCMTLVideoView,
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
