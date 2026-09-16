import Foundation
import Combine

@MainActor
final class ViewerModerationService: ObservableObject {
    static let shared = ViewerModerationService()

    struct Viewer: Identifiable {
        let id: String
        var clientId: String { id }
        var status: Status
        let joinedAt: Date

        enum Status: String, Codable {
            case pending
            case approved
            case denied
        }
    }

    @Published private(set) var viewers: [Viewer] = []
    @Published private(set) var pendingCount = 0
    @Published private(set) var approvedCount = 0

    private weak var signalingService: SignalingService?
    private var messageSubscription: AnyCancellable?

    private init() {}

    func bind(to signalingService: SignalingService) {
        self.signalingService = signalingService
    }

    func reset() {
        viewers.removeAll()
        updateCounts()
    }

    func approve(viewer: Viewer) {
        sendModerationAction(action: "approve", clientId: viewer.clientId)
        updateViewerStatus(viewer.clientId, to: .approved)
    }

    func deny(viewer: Viewer) {
        sendModerationAction(action: "deny", clientId: viewer.clientId)
        updateViewerStatus(viewer.clientId, to: .denied)
    }

    func kick(viewer: Viewer) {
        sendModerationAction(action: "kick", clientId: viewer.clientId)
        viewers.removeAll { $0.clientId == viewer.clientId }
        updateCounts()
    }

    func handleViewerList(_ data: [String: Any]) {
        guard let viewerArray = data["viewers"] as? [[String: Any]] else { return }

        var updatedViewers: [Viewer] = []
        for viewerData in viewerArray {
            guard let clientId = viewerData["clientId"] as? String else { continue }
            guard let statusString = viewerData["status"] as? String,
                  let status = Viewer.Status(rawValue: statusString) else { continue }
            guard let timestamp = viewerData["joinedAt"] as? Int else { continue }

            let joinedAt = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000.0)
            let viewer = Viewer(id: clientId, status: status, joinedAt: joinedAt)
            updatedViewers.append(viewer)
        }

        self.viewers = updatedViewers.sorted { $0.joinedAt > $1.joinedAt }
        updateCounts()

        NSLog("BlinkCast moderation viewer list updated count=\(self.viewers.count) pending=\(self.pendingCount)")
    }

    func handleJoinRequest(_ data: [String: Any]) {
        let viewerInfo = data["viewer"] as? [String: Any] ?? data
        guard let clientId = viewerInfo["clientId"] as? String, !clientId.isEmpty else { return }

        if let existingIndex = viewers.firstIndex(where: { $0.clientId == clientId }) {
            if viewers[existingIndex].status != .approved {
                viewers[existingIndex].status = .pending
            }
        } else {
            viewers.append(Viewer(id: clientId, status: .pending, joinedAt: Date()))
        }

        viewers.sort { $0.joinedAt > $1.joinedAt }
        updateCounts()
    }

    private func sendModerationAction(action: String, clientId: String) {
        let payload: [String: Any] = [
            "type": "moderate",
            "action": action,
            "clientId": clientId
        ]
        signalingService?.sendJSON(payload)
    }

    private func updateViewerStatus(_ clientId: String, to status: Viewer.Status) {
        if let index = viewers.firstIndex(where: { $0.clientId == clientId }) {
            viewers[index].status = status
            updateCounts()
        }
    }

    private func updateCounts() {
        pendingCount = viewers.filter { $0.status == .pending }.count
        approvedCount = viewers.filter { $0.status == .approved }.count
    }
}
