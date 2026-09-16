import Foundation
import Combine

@MainActor
final class RoomAnalyticsService: ObservableObject {
    static let shared = RoomAnalyticsService()

    struct RoomStats {
        let totalViewers: Int
        let approvedViewers: Int
        let pendingViewers: Int
        let totalBitrate: Int64
        let averageLatency: Int
        let averagePacketLoss: Double
        let isHostActive: Bool
        let sessionDuration: TimeInterval
        let peakViewerCount: Int
    }

    @Published private(set) var stats: RoomStats?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastUpdate: Date?

    private weak var signalingService: SignalingService?
    private var analyticsRefreshTask: Task<Void, Never>?

    private init() {}

    func bind(to signalingService: SignalingService) {
        self.signalingService = signalingService
    }

    func startPeriodicAnalytics(interval: TimeInterval = 5.0) {
        guard analyticsRefreshTask == nil else { return }

        analyticsRefreshTask = Task {
            while !Task.isCancelled {
                await requestAnalytics()
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func stopPeriodicAnalytics() {
        analyticsRefreshTask?.cancel()
        analyticsRefreshTask = nil
    }

    func requestAnalytics() async {
        guard let signalingService else { return }

        isRefreshing = true
        signalingService.sendJSON([
            "type": "analytics-request"
        ])
        isRefreshing = false
    }

    func handleRoomAnalytics(_ data: [String: Any]) {
        guard let analyticsData = data["analytics"] as? [String: Any] else { return }

        let stats = RoomStats(
            totalViewers: (analyticsData["totalViewers"] as? Int) ?? 0,
            approvedViewers: (analyticsData["approvedViewers"] as? Int) ?? 0,
            pendingViewers: (analyticsData["pendingViewers"] as? Int) ?? 0,
            totalBitrate: Int64((analyticsData["totalBitrate"] as? Int) ?? 0),
            averageLatency: (analyticsData["averageLatency"] as? Int) ?? 0,
            averagePacketLoss: (analyticsData["averagePacketLoss"] as? Double) ?? 0,
            isHostActive: (analyticsData["isHostActive"] as? Bool) ?? false,
            sessionDuration: TimeInterval((analyticsData["sessionDuration"] as? Int) ?? 0) / 1000.0,
            peakViewerCount: (analyticsData["peakViewerCount"] as? Int) ?? 0
        )

        self.stats = stats
        self.lastUpdate = Date()

        NSLog("BlinkCast room analytics: viewers=\(stats.totalViewers) bitrate=\(stats.totalBitrate)bps latency=\(stats.averageLatency)ms")
    }
}
