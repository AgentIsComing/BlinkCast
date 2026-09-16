import Foundation
import Combine

@MainActor
final class JoinCodeService: ObservableObject {
    static let shared = JoinCodeService()

    enum JoinState: Equatable {
        case idle
        case resolving
        case connecting
        case waitingForHost
        case connected
        case failed(String)
    }

    struct ResolvedRoom {
        let roomID: String
        let signalURL: String
        let sessionToken: String?
        let joinCode: String?
    }

    @Published private(set) var joinState: JoinState = .idle
    @Published private(set) var joinedRoom: ResolvedRoom?

    private let signalingService = SignalingService.shared

    private let defaultCodeServiceURL =
        "https://blinkcast-signaling.jaydenrmaine.workers.dev"

    private init() {
        signalingService.onBroadcastEnded = { [weak self] in
            self?.joinedRoom = nil
            self?.joinState = .failed("The host ended the session.")
        }
    }

    @discardableResult
    func joinCode(_ code: String, password: String = "") async -> Bool {
        let normalizedCode = String(
            code.filter(\.isNumber).prefix(5)
        )

        guard normalizedCode.count == 5 else {
            joinState = .failed("Enter a valid 5-digit join code.")
            return false
        }

        joinState = .resolving

        do {
            let room = try await resolveCode(normalizedCode, password: password)
            return connect(to: room)
        } catch {
            joinedRoom = nil
            joinState = .failed(error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func joinRoom(
        name: String,
        password: String
    ) async -> Bool {
        let roomID = name.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).lowercased()

        guard !roomID.isEmpty else {
            joinState = .failed("Enter a Room ID.")
            return false
        }

        guard !password.isEmpty else {
            joinState = .failed("Enter the room password.")
            return false
        }

        joinState = .resolving

        do {
            let room = try await resolveRoom(
                roomID: roomID,
                password: password
            )
            return connect(to: room)
        } catch {
            joinedRoom = nil
            joinState = .failed(error.localizedDescription)
            return false
        }
    }

    func leaveSession() {
        signalingService.disconnect()
        joinedRoom = nil
        joinState = .idle
    }

    func resetJoinState() {
        if joinedRoom == nil {
            joinState = .idle
        }
    }

    func updateFromSignaling() {
        switch signalingService.state {
        case .disconnected:
            if joinedRoom != nil {
                joinState = .failed("Disconnected from signaling.")
            }

        case .connecting:
            joinState = .connecting

        case .connected:
            joinState = .connecting

        case .joined:
            joinState = .connected

        case .waitingForHost:
            joinState = .waitingForHost

        case .failed(let message):
            joinState = .failed(message)
        }
    }

    private func connect(to room: ResolvedRoom) -> Bool {
        joinedRoom = room
        joinState = .connecting

        signalingService.connect(
            signalURL: room.signalURL,
            roomID: room.roomID,
            role: .viewer,
            sessionToken: room.sessionToken,
            joinCode: room.joinCode
        )

        return true
    }

    private func resolveCode(_ code: String, password: String) async throws -> ResolvedRoom {
        var payload: [String: Any] = ["code": code]
        if !password.isEmpty {
            payload["password"] = password
        }
        let object = try await postJSON(
            path: "/resolve",
            payload: payload
        )

        guard
            let wsURL = object["wsUrl"] as? String,
            !wsURL.isEmpty,
            let roomID = object["roomId"] as? String,
            !roomID.isEmpty
        else {
            throw JoinError.invalidResponse
        }

        let sessionToken = object["sessionToken"] as? String
        guard validateSessionToken(sessionToken, roomID: roomID, code: code) else {
            throw JoinError.server("The session token is invalid or expired.")
        }

        return ResolvedRoom(
            roomID: roomID,
            signalURL: wsURL,
            sessionToken: sessionToken,
            joinCode: code
        )
    }

    private func resolveRoom(
        roomID: String,
        password: String
    ) async throws -> ResolvedRoom {
        let object = try await postJSON(
            path: "/resolve-room",
            payload: [
                "roomId": roomID,
                "password": password
            ]
        )

        guard
            let wsURL = object["wsUrl"] as? String,
            !wsURL.isEmpty
        else {
            throw JoinError.invalidResponse
        }

        let resolvedRoomID =
            (object["roomId"] as? String)?.isEmpty == false
                ? object["roomId"] as! String
                : roomID

        let sessionToken = object["sessionToken"] as? String
        guard validateSessionToken(sessionToken, roomID: resolvedRoomID, code: "") else {
            throw JoinError.server("The room authorization is invalid or expired.")
        }

        return ResolvedRoom(
            roomID: resolvedRoomID,
            signalURL: wsURL,
            sessionToken: sessionToken,
            joinCode: ""
        )
    }

    private func validateSessionToken(_ token: String?, roomID: String, code: String) -> Bool {
        guard let token, !token.isEmpty else {
            NSLog("BlinkCast TOKEN VALIDATE FAIL: token is nil or empty")
            return false
        }
        let parts = token.split(separator: ".")
        guard parts.count == 3 else {
            NSLog("BlinkCast TOKEN VALIDATE FAIL: expected 3 parts, got \(parts.count) token=\(token)")
            return false
        }

        let payloadSegment = String(parts[1])
        guard let payloadData = decodeBase64URL(payloadSegment),
              let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
        else {
            NSLog("BlinkCast TOKEN VALIDATE FAIL: could not decode payload segment=\(payloadSegment)")
            return false
        }

        guard let tokenRoomID = payload["roomId"] as? String,
              tokenRoomID == roomID,
              let purpose = payload["purpose"] as? String,
              purpose == "resolve",
              let tokenCode = payload["code"] as? String,
              (code.isEmpty || tokenCode == code),
              let expValue = payload["exp"] as? NSNumber,
              expValue.intValue > Int(Date().timeIntervalSince1970)
        else {
            NSLog("BlinkCast TOKEN VALIDATE FAIL: claim mismatch payload=\(payload) expectedRoomID=\(roomID) expectedCode=\(code)")
            return false
        }

        NSLog("BlinkCast TOKEN VALIDATE OK: roomID=\(tokenRoomID) purpose=\(payload["purpose"] ?? "nil") exp=\(expValue.intValue)")
        return true
    }

    private func decodeBase64URL(_ value: String) -> Data? {
        var normalized = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = normalized.count % 4
        if remainder > 0 {
            normalized += String(repeating: "=", count: 4 - remainder)
        }

        guard let data = Data(base64Encoded: normalized) else {
            return nil
        }
        return data
    }

    private func postJSON(
        path: String,
        payload: [String: Any]
    ) async throws -> [String: Any] {
        guard let url = URL(string: defaultCodeServiceURL + path) else {
            throw JoinError.invalidServiceURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = try JSONSerialization.data(
            withJSONObject: payload
        )

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw JoinError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw JoinError.server(extractErrorMessage(from: data))
        }

        guard
            let object = try JSONSerialization.jsonObject(with: data)
                as? [String: Any]
        else {
            throw JoinError.invalidResponse
        }

        return object
    }

    private func extractErrorMessage(from data: Data) -> String {
        guard
            let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any],
            let error = object["error"] as? String
        else {
            return "The session could not be resolved."
        }

        return error
    }

    enum JoinError: LocalizedError {
        case invalidServiceURL
        case invalidResponse
        case server(String)

        var errorDescription: String? {
            switch self {
            case .invalidServiceURL:
                return "Invalid code service URL."
            case .invalidResponse:
                return "The room service returned an invalid response."
            case .server(let message):
                return message
            }
        }
    }
}
