import Foundation
import ReplayKit
@preconcurrency import WebRTC

final class BroadcastWebRTCSession: NSObject, @unchecked Sendable {
    private let factory: RTCPeerConnectionFactory
    private let videoSource: RTCVideoSource
    private let videoCapturer: RTCVideoCapturer
    private var peerConnection: RTCPeerConnection?
    private var socket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var roomID = ""
    private var clientID = "host-broadcast-\(UUID().uuidString.lowercased().prefix(8))"
    private var remoteClientID: String?
    private var pendingCandidates: [RTCIceCandidate] = []

    override init() {
        blinkExtensionLog("BlinkCast EXTENSION session init begin")
        RTCInitializeSSL()
        factory = RTCPeerConnectionFactory(
            encoderFactory: RTCDefaultVideoEncoderFactory(),
            decoderFactory: RTCDefaultVideoDecoderFactory()
        )
        videoSource = factory.videoSource()
        videoCapturer = RTCVideoCapturer(delegate: videoSource)
        super.init()
        blinkExtensionLog("BlinkCast EXTENSION session init complete")
    }

    func start() {
        blinkExtensionLog("BlinkCast EXTENSION session start begin")
        guard let defaults = UserDefaults(suiteName: "group.JaysApps.BlinkCast") else {
            blinkExtensionLog("BlinkCast EXTENSION ERROR App Group unavailable")
            return
        }
        let signalValue = defaults.string(forKey: "signalURL")
        let roomValue = defaults.string(forKey: "roomID")
        let clientValue = defaults.string(forKey: "clientID")
        blinkExtensionLog("BlinkCast EXTENSION App Group read signalPresent=\(signalValue != nil) roomPresent=\(roomValue != nil) clientPresent=\(clientValue != nil)")
        guard let signalURL = signalValue,
              let roomID = roomValue,
              let url = URL(string: signalURL) else {
            blinkExtensionLog("BlinkCast EXTENSION ERROR App Group missing or invalid signalURL=\(signalValue ?? "nil") roomID=\(roomValue ?? "nil")")
            blinkExtensionLog("BlinkCast broadcast is missing shared session configuration")
            return
        }

        blinkExtensionLog("BlinkCast EXTENSION transport starting room=\(roomID) signalHost=\(url.host ?? "nil") signalPath=\(url.path)")

        self.roomID = roomID
        if let savedClientID = defaults.string(forKey: "clientID"),
           !savedClientID.isEmpty {
            clientID = savedClientID
        }
        blinkExtensionLog("BlinkCast EXTENSION identity clientID=\(clientID)")
        let configuration = URLSessionConfiguration.default
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session

        guard var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            blinkExtensionLog("BlinkCast EXTENSION ERROR could not create URL components")
            return
        }
        components.queryItems = (components.queryItems ?? [])
            .filter { $0.name != "roomId" }
        components.queryItems?.append(URLQueryItem(name: "roomId", value: roomID))

        guard let socketURL = components.url else {
            blinkExtensionLog("BlinkCast EXTENSION ERROR could not create WebSocket URL")
            return
        }
        blinkExtensionLog("BlinkCast EXTENSION WebSocket URL prepared host=\(socketURL.host ?? "nil") path=\(socketURL.path) queryPresent=\(socketURL.query != nil)")
        let socket = session.webSocketTask(with: socketURL)
        self.socket = socket
        socket.resume()
        blinkExtensionLog("BlinkCast EXTENSION WebSocket task resumed clientID=\(clientID)")
        receiveNextMessage()
    }

    func stop() {
        blinkExtensionLog("BlinkCast EXTENSION session stop socketPresent=\(socket != nil) peerPresent=\(peerConnection != nil)")
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        session?.invalidateAndCancel()
        session = nil
        peerConnection?.close()
        peerConnection = nil
    }

    func capture(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            blinkExtensionLog("BlinkCast EXTENSION ERROR sample had no pixel buffer")
            return
        }
        let timestamp = Int64(CMTimeGetSeconds(sampleBuffer.presentationTimeStamp) * 1_000_000_000)
        let frame = RTCVideoFrame(
            buffer: RTCCVPixelBuffer(pixelBuffer: pixelBuffer),
            rotation: ._270,
            timeStampNs: timestamp
        )
        RTCDispatcher.dispatchAsync(on: .typeCaptureSession) { [weak self] in
            guard let self else { return }
            self.videoSource.capturer(self.videoCapturer, didCapture: frame)
        }
    }

    private func receiveNextMessage() {
        guard let socket else {
            blinkExtensionLog("BlinkCast EXTENSION ERROR receive skipped socket missing")
            return
        }
        socket.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                blinkExtensionLog("BlinkCast EXTENSION signaling message received kind=\(messageKind(message))")
                self.handle(message)
                self.receiveNextMessage()
            case .failure(let error):
                blinkExtensionLog("BlinkCast EXTENSION ERROR signaling receive failed error=\(error.localizedDescription)")
            }
        }
    }

    private func messageKind(_ message: URLSessionWebSocketTask.Message) -> String {
        switch message {
        case .string:
            return "string"
        case .data:
            return "data"
        @unknown default:
            return "unknown"
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .string(let value):
            guard let converted = value.data(using: .utf8) else { return }
            data = converted
        case .data(let value):
            data = value
        @unknown default:
            return
        }

          guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else {
                        blinkExtensionLog("BlinkCast EXTENSION ERROR signaling message invalid JSON")
            return
          }

                blinkExtensionLog("BlinkCast EXTENSION handling signaling type=\(type) keys=\(object.keys.sorted())")

        switch type {
        case "joined", "host-available":
            NSLog("BlinkCast broadcast joined signaling room")
            break
        case "viewer-joined":
            let viewerID = (object["viewer"] as? [String: Any])?["clientId"] as? String
                ?? "unknown"
            blinkExtensionLog("BlinkCast EXTENSION viewer joined clientID=\(viewerID); waiting for viewer offer")
        case "signal":
            guard let signal = object["data"] as? [String: Any] else {
                blinkExtensionLog("BlinkCast EXTENSION ERROR signal message missing data")
                return
            }
            handleSignal(signal)
        default:
            blinkExtensionLog("BlinkCast EXTENSION ignoring signaling type=\(type)")
            break
        }
    }

    private func handleSignal(_ signal: [String: Any]) {
        if let target = signal["to"] as? String, !target.isEmpty, target != clientID {
            blinkExtensionLog("BlinkCast EXTENSION ignoring signal targetedTo=\(target) localClientID=\(clientID)")
            return
        }
        guard let offer = signal["offer"] as? [String: Any],
              let sdp = offer["sdp"] as? String else {
            if let candidate = signal["candidate"] as? [String: Any] {
                blinkExtensionLog("BlinkCast EXTENSION received ICE candidate")
                addCandidate(candidate)
            } else {
                blinkExtensionLog("BlinkCast EXTENSION signal had neither offer nor candidate keys=\(signal.keys.sorted())")
            }
            return
        }

        remoteClientID = signal["from"] as? String
        blinkExtensionLog("BlinkCast EXTENSION received viewer offer from=\(remoteClientID ?? "unknown") sdpLength=\(sdp.count)")
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "false",
                "OfferToReceiveVideo": "false"
            ],
            optionalConstraints: nil
        )
        guard let peerConnection = factory.peerConnection(
            with: makeConfiguration(),
            constraints: constraints,
            delegate: self
        ) else {
            blinkExtensionLog("BlinkCast EXTENSION ERROR could not create peer connection")
            return
        }

        self.peerConnection = peerConnection
        blinkExtensionLog("BlinkCast EXTENSION peer connection created and screen track added")
        let track = factory.videoTrack(with: videoSource, trackId: "blinkcast-screen")
        _ = peerConnection.add(track, streamIds: ["blinkcast-stream"])
        peerConnection.setRemoteDescription(
            RTCSessionDescription(type: .offer, sdp: sdp)
        ) { [weak self] error in
            guard let self else { return }
            if let error {
                blinkExtensionLog("BlinkCast EXTENSION ERROR set remote offer failed error=\(error.localizedDescription)")
                return
            }
            blinkExtensionLog("BlinkCast EXTENSION remote offer set")
            peerConnection.answer(for: constraints) { [weak self] answer, error in
                guard let self else { return }
                if let error {
                    blinkExtensionLog("BlinkCast EXTENSION ERROR answer creation failed error=\(error.localizedDescription)")
                    return
                }
                guard let answer else {
                    blinkExtensionLog("BlinkCast EXTENSION ERROR answer was nil without error")
                    return
                }
                blinkExtensionLog("BlinkCast EXTENSION answer created sdpLength=\(answer.sdp.count)")
                peerConnection.setLocalDescription(answer) { [weak self] error in
                    guard let self else { return }
                    if let error {
                        blinkExtensionLog("BlinkCast EXTENSION ERROR set local answer failed error=\(error.localizedDescription)")
                        return
                    }
                    self.sendSignal([
                        "from": self.clientID,
                        "to": self.remoteClientID as Any,
                        "answer": ["type": "answer", "sdp": answer.sdp]
                    ])
                    blinkExtensionLog("BlinkCast EXTENSION sent viewer answer")
                    self.flushCandidates()
                }
            }
        }
    }

    private func addCandidate(_ payload: [String: Any]) {
        guard let sdp = payload["candidate"] as? String else {
            blinkExtensionLog("BlinkCast EXTENSION ERROR ICE candidate missing SDP")
            return
        }
        let lineIndex = (payload["sdpMLineIndex"] as? NSNumber)?.int32Value ?? 0
        let candidate = RTCIceCandidate(
            sdp: sdp,
            sdpMLineIndex: lineIndex,
            sdpMid: payload["sdpMid"] as? String
        )
        guard let peerConnection, peerConnection.remoteDescription != nil else {
            blinkExtensionLog("BlinkCast EXTENSION queued ICE candidate remoteDescriptionPresent=\(peerConnection?.remoteDescription != nil)")
            pendingCandidates.append(candidate)
            return
        }
        blinkExtensionLog("BlinkCast EXTENSION adding ICE candidate immediately")
        peerConnection.add(candidate)
    }

    private func flushCandidates() {
        guard let peerConnection, peerConnection.remoteDescription != nil else {
            blinkExtensionLog("BlinkCast EXTENSION flush ICE skipped peer or remote description missing pending=\(pendingCandidates.count)")
            return
        }
        blinkExtensionLog("BlinkCast EXTENSION flushing ICE candidates count=\(pendingCandidates.count)")
        pendingCandidates.forEach { peerConnection.add($0) }
        pendingCandidates.removeAll()
    }

    private func sendJoin() {
        blinkExtensionLog("BlinkCast EXTENSION sending join role=host room=\(roomID) clientID=\(clientID)")
        send(["type": "join", "role": "host", "roomId": roomID, "clientId": clientID])
    }

    private func sendSignal(_ data: [String: Any]) {
        send(["type": "signal", "data": data])
    }

    private func send(_ payload: [String: Any]) {
        guard let socket else {
            blinkExtensionLog("BlinkCast EXTENSION ERROR send skipped socket missing type=\(payload["type"] as? String ?? "unknown")")
            return
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let string = String(data: data, encoding: .utf8) else {
            blinkExtensionLog("BlinkCast EXTENSION ERROR send JSON serialization failed type=\(payload["type"] as? String ?? "unknown")")
            return
        }
        blinkExtensionLog("BlinkCast EXTENSION sending type=\(payload["type"] as? String ?? "unknown") bytes=\(data.count)")
        socket.send(.string(string)) { error in
            if let error {
                blinkExtensionLog("BlinkCast EXTENSION ERROR signaling send failed error=\(error.localizedDescription)")
            } else {
                blinkExtensionLog("BlinkCast EXTENSION signaling send completed type=\(payload["type"] as? String ?? "unknown")")
            }
        }
    }

    private func makeConfiguration() -> RTCConfiguration {
        let configuration = RTCConfiguration()
        configuration.sdpSemantics = .unifiedPlan
        configuration.bundlePolicy = .maxBundle
        configuration.iceCandidatePoolSize = 1
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
        return configuration
    }
}

extension BroadcastWebRTCSession: URLSessionWebSocketDelegate {
    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocolName: String?
    ) {
        blinkExtensionLog("BlinkCast EXTENSION WebSocket opened protocol=\(protocolName ?? "nil")")
        sendJoin()
    }
}

extension BroadcastWebRTCSession: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        blinkExtensionLog("BlinkCast EXTENSION WebRTC signalingState=\(stateChanged.rawValue)")
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        blinkExtensionLog("BlinkCast EXTENSION WebRTC iceConnectionState=\(newState.rawValue)")
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        blinkExtensionLog("BlinkCast EXTENSION WebRTC iceGatheringState=\(newState.rawValue)")
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        blinkExtensionLog("BlinkCast EXTENSION WebRTC generated ICE candidate")
        var payload: [String: Any] = [
            "from": clientID,
            "candidate": [
                "candidate": candidate.sdp,
                "sdpMLineIndex": Int(candidate.sdpMLineIndex)
            ]
        ]
        if let remoteClientID { payload["to"] = remoteClientID }
        if let sdpMid = candidate.sdpMid {
            var candidatePayload = payload["candidate"] as? [String: Any] ?? [:]
            candidatePayload["sdpMid"] = sdpMid
            payload["candidate"] = candidatePayload
        }
        sendSignal(payload)
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}
