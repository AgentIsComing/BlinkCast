import Foundation
import Combine
@preconcurrency import WebRTC

@MainActor
final class NetworkDiagnostics: ObservableObject {
    static let shared = NetworkDiagnostics()

    enum NetworkQuality: String, Codable {
        case excellent
        case good
        case fair
        case poor
        case unknown
    }

    struct ICEMetrics: Codable {
        let state: String
        let candidateTypes: [String]
        let selectedCandidatePairInfo: String?
        let connectionTime: TimeInterval
    }

    struct SessionMetrics: Codable {
        let sessionID: String
        let roomID: String
        let clientID: String
        let role: String
        let startTime: Date
        let duration: TimeInterval
        let networkQuality: NetworkQuality
        let iceState: String
        let candidateCount: Int
        let reconnectAttempts: Int
        let lastError: String?
        let iceMetrics: ICEMetrics?
    }

    @Published private(set) var networkQuality: NetworkQuality = .unknown
    @Published private(set) var iceState: String = "new"
    @Published private(set) var estimatedBitrate: Int64 = 0
    @Published private(set) var jitter: Double = 0
    @Published private(set) var packetLoss: Double = 0
    @Published private(set) var roundTripTime: Int64 = 0
    @Published private(set) var candidateCount: Int = 0
    @Published private(set) var connectionRoute = "Unknown"

    private var sessionID = UUID().uuidString
    private var metricsCollection: Task<Void, Never>?
    private var peerConnection: RTCPeerConnection?
    private weak var webrtcService: WebRTCService?
    private weak var signalingService: SignalingService?
    private var previousBytesReceived: Int64 = 0
    private var previousStatsTimestamp: TimeInterval = 0

    private init() {}

    func bind(to webrtcService: WebRTCService, signalingService: SignalingService) {
        self.webrtcService = webrtcService
        self.signalingService = signalingService
    }

    func setPeerConnection(_ peerConnection: RTCPeerConnection?) {
        self.peerConnection = peerConnection

        if peerConnection != nil {
            startMetricsCollection()
        } else {
            stopMetricsCollection()
        }
    }

    private func startMetricsCollection() {
        metricsCollection?.cancel()
        metricsCollection = Task {
            while !Task.isCancelled {
                await collectMetrics()
                await reportMetricsToBackend()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func stopMetricsCollection() {
        metricsCollection?.cancel()
        metricsCollection = nil
    }

    private func collectMetrics() async {
        guard let peerConnection else { return }

        let rtcStats = await withCheckedContinuation { continuation in
            peerConnection.statistics { stats in
                continuation.resume(returning: stats)
            }
        }

        var totalBytesReceived: Int64 = 0
        var totalJitter: Double = 0
        var totalPacketLoss: Double = 0
        var totalRTT: Int64 = 0
        var statsCount = 0
        var candidateTypes: [String] = []
        var route = "Unknown"

        for (_, stat) in rtcStats.statistics {
            let values = stat.values
            let statsType = stat.type
            let number = { (key: String) -> Double? in
                (values[key] as? NSNumber)?.doubleValue
            }

            if statsType == "inbound-rtp" || statsType == "outbound-rtp" {
                totalBytesReceived += Int64(number("bytesReceived") ?? number("bytesSent") ?? 0)
                totalJitter += number("jitter") ?? 0
                let lost = number("packetsLost") ?? 0
                let received = number("packetsReceived") ?? 0
                if received + lost > 0 {
                    totalPacketLoss += lost / (received + lost)
                }
                statsCount += 1
            } else if statsType == "candidate-pair" {
                if let rtt = number("currentRoundTripTime") {
                    totalRTT = max(totalRTT, Int64(rtt * 1000))
                }
                if let localType = values["localCandidateType"] as? String {
                    candidateTypes.append(localType)
                }
                if let relayProtocol = values["relayProtocol"] as? String {
                    route = relayProtocol == "tls" ? "TLS relay" : relayProtocol == "tcp" ? "TCP relay" : "UDP relay"
                } else if candidateTypes.contains("relay") {
                    route = "UDP relay"
                } else if !candidateTypes.isEmpty {
                    route = "Direct"
                }
            } else if statsType == "local-candidate" || statsType == "remote-candidate" {
                if let candidateType = values["candidateType"] as? String {
                    candidateTypes.append(candidateType)
                }
            }
        }

        let statsTimestamp = Date().timeIntervalSince1970
        let elapsed = statsTimestamp - previousStatsTimestamp
        let bitrate = elapsed > 0 && totalBytesReceived >= previousBytesReceived
            ? Int64(Double(totalBytesReceived - previousBytesReceived) * 8 / elapsed)
            : 0
        previousBytesReceived = totalBytesReceived
        previousStatsTimestamp = statsTimestamp

        await MainActor.run {
            self.estimatedBitrate = bitrate
            self.jitter = statsCount > 0 ? totalJitter / Double(statsCount) : 0
            self.packetLoss = statsCount > 0 ? totalPacketLoss / Double(statsCount) : 0
            self.roundTripTime = totalRTT
            self.connectionRoute = route
            self.networkQuality = determineNetworkQuality(
                bitrate: bitrate,
                packetLoss: self.packetLoss,
                rtt: totalRTT
            )
        }
    }

    private func determineNetworkQuality(bitrate: Int64, packetLoss: Double, rtt: Int64) -> NetworkQuality {
        let bitrateMbps = Double(bitrate) / 1_000_000
        let isHighPacketLoss = packetLoss > 0.05
        let isHighLatency = rtt > 150

        if bitrateMbps < 1 || isHighPacketLoss || isHighLatency {
            return .poor
        } else if bitrateMbps < 2.5 {
            return .fair
        } else if bitrateMbps < 5 {
            return .good
        } else {
            return .excellent
        }
    }

    func snapshot() -> SessionMetrics? {
        guard let webrtcService else { return nil }

        return SessionMetrics(
            sessionID: sessionID,
            roomID: "", // Will be populated from SignalingService
            clientID: "", // Will be populated from SignalingService
            role: "", // Will be populated from SignalingService
            startTime: Date(),
            duration: 0,
            networkQuality: networkQuality,
            iceState: iceState,
            candidateCount: candidateCount,
            reconnectAttempts: 0,
            lastError: nil,
            iceMetrics: nil
        )
    }

    private func reportMetricsToBackend() async {
        guard let signalingService,
              signalingService.state == .joined else {
            return
        }

        let payload: [String: Any] = [
            "type": "viewer-metrics",
            "bitrate": estimatedBitrate,
            "packetLoss": packetLoss,
            "rtt": roundTripTime,
            "networkQuality": networkQuality.rawValue
        ]

        signalingService.sendJSON(payload)
    }
}
