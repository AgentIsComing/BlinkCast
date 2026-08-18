import Foundation
import Combine

@MainActor
final class SignalingService: NSObject, ObservableObject {
    static let shared = SignalingService()

    enum Role: String {
        case host
        case viewer
    }

    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case joined
        case waitingForHost
        case failed(String)
    }

    struct SignalEnvelope {
        let data: [String: Any]
    }

    @Published private(set) var state: ConnectionState = .disconnected
    @Published private(set) var hostAvailable = false
    @Published private(set) var reconnectAttempt = 0

    var onSignal: ((SignalEnvelope) -> Void)?
    var onViewerJoined: (() -> Void)?
    var onBroadcastEnded: (() -> Void)?

    var currentClientID: String {
        clientID
    }

    var currentRole: Role {
        role
    }

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?

    private var signalURL: URL?
    private var roomID = ""
    private var role: Role = .viewer
    private var clientID = ""
    private var shouldReconnect = false
    private var reconnectTask: Task<Void, Never>?

    private override init() {
        super.init()
    }

    func connect(
        signalURL: String,
        roomID: String,
        role: Role
    ) {
        disconnect()
        shouldReconnect = true

        guard let normalizedURL = normalizeSignalURL(signalURL) else {
            state = .failed("Invalid signaling URL.")
            return
        }

        self.signalURL = normalizedURL
        self.roomID = roomID
        self.role = role
        self.clientID = "\(role.rawValue)-\(UUID().uuidString.lowercased().prefix(8))"
        reconnectAttempt = 0

        state = .connecting
        hostAvailable = false

        let configuration = URLSessionConfiguration.default
        let session = URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: nil
        )

        urlSession = session

        let task = session.webSocketTask(with: normalizedURL)
        webSocketTask = task
        task.resume()

        receiveNextMessage()
    }

    func disconnect() {
        shouldReconnect = false
        reconnectTask?.cancel()
        reconnectTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil

        urlSession?.invalidateAndCancel()
        urlSession = nil

        state = .disconnected
        hostAvailable = false
        reconnectAttempt = 0
    }

    func sendSignal(_ data: [String: Any]) {
        sendJSON([
            "type": "signal",
            "data": data
        ])
    }

    func sendBroadcastEnd() {
        guard role == .host else {
            return
        }

        sendJSON([
            "type": "broadcast-end"
        ])
    }

    private func sendJoin() {
        let payload: [String: Any] = [
            "type": "join",
            "role": role.rawValue,
            "roomId": roomID,
            "clientId": clientID
        ]

        sendJSON(payload)
    }

    private func sendJSON(_ payload: [String: Any]) {
        guard
            let webSocketTask,
            JSONSerialization.isValidJSONObject(payload)
        else {
            return
        }

        do {
            let data = try JSONSerialization.data(withJSONObject: payload)

            guard let string = String(data: data, encoding: .utf8) else {
                return
            }

            webSocketTask.send(.string(string)) { [weak self] error in
                guard let error else {
                    return
                }

                Task { @MainActor in
                    self?.state = .failed(error.localizedDescription)
                }
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func receiveNextMessage() {
        guard let webSocketTask else {
            return
        }

        webSocketTask.receive { [weak self] result in
            guard let self else {
                return
            }

            switch result {
            case .success(let message):
                Task { @MainActor in
                    self.handle(message)
                    self.receiveNextMessage()
                }

            case .failure(let error):
                Task { @MainActor in
                    self.handleTransportFailure(error)
                }
            }
        }
    }

    private func handleTransportFailure(_ error: Error) {
        guard shouldReconnect else {
            state = .failed(error.localizedDescription)
            return
        }

        scheduleReconnect(message: error.localizedDescription)
    }

    private func scheduleReconnect(message: String) {
        guard reconnectTask == nil,
              shouldReconnect,
              let signalURL,
              !roomID.isEmpty else {
            state = .failed(message)
            return
        }

        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        state = .connecting
        reconnectAttempt += 1

        let attempt = reconnectAttempt
        let delay = min(pow(2.0, Double(attempt - 1)), 30.0)
        reconnectTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }

            guard let self,
                  self.shouldReconnect else {
                return
            }

            self.reconnectTask = nil
            self.connect(
                signalURL: signalURL.absoluteString,
                roomID: self.roomID,
                role: self.role
            )
            self.reconnectAttempt = attempt
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let data: Data

        switch message {
        case .string(let string):
            guard let converted = string.data(using: .utf8) else {
                return
            }
            data = converted

        case .data(let rawData):
            data = rawData

        @unknown default:
            return
        }

        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let dictionary = object as? [String: Any],
            let type = dictionary["type"] as? String
        else {
            return
        }

        switch type {
        case "joined":
            state = .joined

            if let available = dictionary["hostAvailable"] as? Bool {
                hostAvailable = available

                if role == .viewer && !available {
                    state = .waitingForHost
                }
            }

        case "host-available":
            hostAvailable = true
            state = .joined

        case "viewer-joined":
            onViewerJoined?()

        case "signal":
            guard let signalData = dictionary["data"] as? [String: Any] else {
                return
            }

            onSignal?(SignalEnvelope(data: signalData))

        case "broadcast-ended":
            state = .disconnected
            onBroadcastEnded?()

        case "error":
            let message = dictionary["message"] as? String
                ?? "Unknown signaling error."
            state = .failed(message)

        default:
            break
        }
    }

    private func normalizeSignalURL(_ value: String) -> URL? {
        var value = value.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !value.isEmpty else {
            return nil
        }

        if value.hasPrefix("https://") {
            value = "wss://" + value.dropFirst("https://".count)
        }

        if value.hasPrefix("http://") {
            value = "ws://" + value.dropFirst("http://".count)
        }

        guard value.hasPrefix("ws://") || value.hasPrefix("wss://") else {
            return nil
        }

        if !value.hasSuffix("/signal") {
            value = value.trimmingCharacters(
                in: CharacterSet(charactersIn: "/")
            )
            value += "/signal"
        }

        return URL(string: value)
    }
}

extension SignalingService: URLSessionWebSocketDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        Task { @MainActor in
            self.reconnectTask?.cancel()
            self.reconnectTask = nil
            self.reconnectAttempt = 0
            self.state = .connected
            self.sendJoin()
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        Task { @MainActor in
            guard self.shouldReconnect else {
                self.state = .disconnected
                return
            }

            let message = reason.flatMap {
                String(data: $0, encoding: .utf8)
            } ?? "Signaling connection closed (\(closeCode.rawValue))."
            self.scheduleReconnect(message: message)
        }
    }
}
