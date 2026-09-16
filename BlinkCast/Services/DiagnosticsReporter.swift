import Foundation
import Combine

@MainActor
final class DiagnosticsReporter: ObservableObject {
    static let shared = DiagnosticsReporter()

    @Published var isReporting = false

    private weak var signalingService: SignalingService?
    private weak var webrtcService: WebRTCService?
    private weak var networkDiagnostics: NetworkDiagnostics?
    private var reportingTask: Task<Void, Never>?
    private var reportingBaseURL: URL?

    private init() {}

    func bind(
        to signalingService: SignalingService,
        webrtcService: WebRTCService,
        networkDiagnostics: NetworkDiagnostics,
        baseURL: URL
    ) {
        self.signalingService = signalingService
        self.webrtcService = webrtcService
        self.networkDiagnostics = networkDiagnostics
        self.reportingBaseURL = baseURL
    }

    func startPeriodicReporting(interval: TimeInterval = 5.0) {
        guard reportingTask == nil else { return }
        isReporting = true

        reportingTask = Task {
            while !Task.isCancelled {
                await sendDiagnosticsReport()
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func stopPeriodicReporting() {
        reportingTask?.cancel()
        reportingTask = nil
        isReporting = false
    }

    func sendDiagnosticsReport() async {
        guard let signalingService,
              let networkDiagnostics,
              let baseURL = reportingBaseURL else {
            return
        }

        let payload: [String: Any] = [
            "roomId": signalingService.currentRoomID.isEmpty ? "unknown" : signalingService.currentRoomID,
            "clientId": signalingService.currentClientID,
            "code": signalingService.currentJoinCode,
            "role": signalingService.currentRole.rawValue,
            "networkQuality": networkDiagnostics.networkQuality.rawValue,
            "iceState": networkDiagnostics.iceState,
            "bitrate": networkDiagnostics.estimatedBitrate,
            "packetLoss": networkDiagnostics.packetLoss,
            "rtt": networkDiagnostics.roundTripTime
        ]

        let diagnosticsURL = baseURL.appending(path: "/diagnostics")
        var request = URLRequest(url: diagnosticsURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = signalingService.currentSessionToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode < 200 || httpResponse.statusCode >= 300 {
                    NSLog("BlinkCast diagnostics report failed status=\(httpResponse.statusCode)")
                } else {
                    NSLog("BlinkCast diagnostics report sent")
                }
            }
        } catch {
            NSLog("BlinkCast diagnostics report error: \(error.localizedDescription)")
        }
    }

    func fetchRoomDiagnostics(roomId: String) async -> [[String: Any]]? {
        guard let baseURL = reportingBaseURL else { return nil }

        var components = URLComponents(
            url: baseURL.appending(path: "/diagnostics/room"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "roomId", value: roomId),
            URLQueryItem(name: "code", value: signalingService?.currentJoinCode ?? "")
        ]
        guard let diagnosticsURL = components?.url else { return nil }

        do {
            var request = URLRequest(url: diagnosticsURL)
            if let token = signalingService?.currentSessionToken {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
                return nil
            }

            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let reports = json["reports"] as? [[String: Any]] {
                return reports
            }
        } catch {
            NSLog("BlinkCast fetch diagnostics error: \(error.localizedDescription)")
        }

        return nil
    }

    func fetchTURNConfiguration(
        from baseURL: URL,
        roomID: String,
        joinCode: String,
        sessionToken: String
    ) async -> (servers: [String], username: String, credential: String)? {
        var components = URLComponents(url: baseURL.appending(path: "/turn-config"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "roomId", value: roomID),
            URLQueryItem(name: "code", value: joinCode)
        ]
        guard let turnURL = components?.url else { return nil }
        var request = URLRequest(url: turnURL)
        request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
                NSLog("BlinkCast TURN config fetch failed")
                return nil
            }

            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let servers = json["servers"] as? [String],
               let username = json["username"] as? String,
               let credential = json["credential"] as? String {
                NSLog("BlinkCast TURN config fetched servers=\(servers.count)")
                return (servers, username, credential)
            }
        } catch {
            NSLog("BlinkCast TURN config fetch error: \(error.localizedDescription)")
        }

        return nil
    }
}
