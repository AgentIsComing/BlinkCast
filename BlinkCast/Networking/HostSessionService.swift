import Foundation
import Combine

@MainActor
final class HostSessionService: ObservableObject {
    static let shared = HostSessionService()

    enum HostState: Equatable {
        case idle
        case publishing
        case connecting
        case ready
        case failed(String)
    }

    @Published private(set) var state: HostState = .idle
    @Published private(set) var sessionCode = "-----"
    @Published private(set) var activeRoomID = ""

    private let signalingService = SignalingService.shared
    private let sessionBindingKey = "sessionSecuritySignature"
    private let sessionExpiryKey = "sessionExpiresAt"

    private let codeServiceURL =
        "https://blinkcast-signaling.jaydenrmaine.workers.dev"

    private init() {}

    @discardableResult
    func startSession(
        signalURL: String,
        requestedRoomID: String,
        password: String,
        requiresApproval: Bool = true
    ) async -> Bool {
        NSLog("BlinkCast HOST startSession signalURL=\(signalURL) requestedRoom=\(requestedRoomID.isEmpty ? "<empty>" : requestedRoomID) passwordPresent=\(!password.isEmpty)")
        let normalizedSignalURL = normalizeSignalURL(signalURL)

        guard let normalizedSignalURL else {
            NSLog("BlinkCast HOST ERROR signal URL normalization failed")
            state = .failed(
                "Enter a valid signaling URL beginning with ws://, wss://, http://, or https://."
            )
            return false
        }

        let trimmedRoomID = requestedRoomID.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).lowercased()

        let roomID = trimmedRoomID.isEmpty
            ? "blink-\(UUID().uuidString.lowercased().prefix(8))"
            : trimmedRoomID

        state = .publishing
        NSLog("BlinkCast HOST registering room=\(roomID) normalizedSignalURL=\(normalizedSignalURL)")

        do {
            let registration = try await registerCode(
                signalURL: normalizedSignalURL,
                roomID: roomID
            )
            NSLog("BlinkCast HOST register code succeeded code=\(registration.code)")

            if !trimmedRoomID.isEmpty && !password.isEmpty {
                guard password.count >= 4 else {
                    throw HostError.invalidPassword
                }

                try await registerRoom(
                    signalURL: normalizedSignalURL,
                    roomID: roomID,
                    password: password
                )
                NSLog("BlinkCast HOST password room registration succeeded")
            }

            sessionCode = registration.code
            activeRoomID = roomID
            let sharedDefaults = UserDefaults(
                suiteName: "group.JaysApps.BlinkCast"
            )
            NSLog("BlinkCast HOST App Group available=\(sharedDefaults != nil)")
            let hostClientID = "host-broadcast-\(UUID().uuidString.lowercased().prefix(8))"
            let nonce = SessionSecurityBinding.generateNonce()
            let expiresAt = SessionSecurityBinding.expiryDate()
            let signature = SessionSecurityBinding.signature(
                roomID: roomID,
                clientID: hostClientID,
                nonce: nonce,
                expiresAt: expiresAt
            )

            sharedDefaults?.set(
                normalizedSignalURL,
                forKey: "signalURL"
            )
            sharedDefaults?.set(roomID, forKey: "roomID")
            sharedDefaults?.set(hostClientID, forKey: "clientID")
            sharedDefaults?.set(nonce, forKey: "sessionNonce")
            sharedDefaults?.set(expiresAt.timeIntervalSince1970, forKey: sessionExpiryKey)
            sharedDefaults?.set(signature, forKey: sessionBindingKey)
            NSLog("BlinkCast HOST App Group wrote signalURL=\(normalizedSignalURL) roomID=\(roomID) clientID=\(hostClientID) expiresAt=\(expiresAt.ISO8601Format()) signaturePresent=\(signature.count > 0)")

            #if os(iOS)
            NSLog("BlinkCast iOS host room ready for broadcast extension")
            state = .ready
            return true
            #else
            state = .connecting

            signalingService.connect(
                signalURL: normalizedSignalURL,
                roomID: roomID,
                role: .host,
                sessionToken: registration.sessionToken,
                joinCode: registration.code,
                requiresApproval: requiresApproval
            )

            return true
            #endif
        } catch {
            NSLog("BlinkCast HOST ERROR startSession failed error=\(error.localizedDescription)")
            sessionCode = "-----"
            activeRoomID = ""
            state = .failed(error.localizedDescription)
            return false
        }
    }

    func updateFromSignaling() {
        switch signalingService.state {
        case .disconnected:
            if activeRoomID.isEmpty {
                state = .idle
            } else if state == .ready || state == .connecting {
                state = .failed("Disconnected from signaling.")
            }

        case .connecting, .connected:
            if !activeRoomID.isEmpty {
                state = .connecting
            }

        case .joined:
            if !activeRoomID.isEmpty {
                state = .ready
            }

        case .waitingForHost:
            break

        case .failed(let message):
            state = .failed(message)
        }
    }

    func endSession() {
        signalingService.sendBroadcastEnd()
        signalingService.disconnect()

        if let sharedDefaults = UserDefaults(suiteName: "group.JaysApps.BlinkCast") {
            sharedDefaults.removeObject(forKey: "signalURL")
            sharedDefaults.removeObject(forKey: "roomID")
            sharedDefaults.removeObject(forKey: "clientID")
            sharedDefaults.removeObject(forKey: "sessionNonce")
            sharedDefaults.removeObject(forKey: sessionExpiryKey)
            sharedDefaults.removeObject(forKey: sessionBindingKey)
        }

        state = .idle
        sessionCode = "-----"
        activeRoomID = ""
    }

    func resetFailure() {
        if case .failed = state, activeRoomID.isEmpty {
            state = .idle
        }
    }

    private func registerCode(
        signalURL: String,
        roomID: String
    ) async throws -> (code: String, sessionToken: String) {
        NSLog("BlinkCast HOST POST /register room=\(roomID)")
        let object = try await postJSON(
            path: "/register",
            payload: [
                "wsUrl": signalURL,
                "roomId": roomID,
                "ttlSeconds": 900
            ]
        )

        guard
            let code = object["code"] as? String,
            code.count == 5,
            let sessionToken = object["sessionToken"] as? String,
            !sessionToken.isEmpty
        else {
            throw HostError.invalidResponse
        }

        return (code, sessionToken)
    }

    private func registerRoom(
        signalURL: String,
        roomID: String,
        password: String
    ) async throws {
        NSLog("BlinkCast HOST POST /register-room room=\(roomID)")
        _ = try await postJSON(
            path: "/register-room",
            payload: [
                "wsUrl": signalURL,
                "roomId": roomID,
                "password": password,
                "ttlSeconds": 900
            ]
        )
    }

    private func postJSON(
        path: String,
        payload: [String: Any]
    ) async throws -> [String: Any] {
        NSLog("BlinkCast HOST HTTP request path=\(path)")
        guard let url = URL(string: codeServiceURL + path) else {
            throw HostError.invalidServiceURL
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
            NSLog("BlinkCast HOST ERROR response was not HTTP path=\(path)")
            throw HostError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            NSLog("BlinkCast HOST ERROR HTTP status=\(httpResponse.statusCode) path=\(path) body=\(String(data: data, encoding: .utf8) ?? "<non-text>")")
            throw HostError.server(extractErrorMessage(from: data))
        }

        guard
            let object = try JSONSerialization.jsonObject(with: data)
                as? [String: Any]
        else {
            NSLog("BlinkCast HOST ERROR response JSON was not dictionary path=\(path)")
            throw HostError.invalidResponse
        }

        return object
    }

    private func normalizeSignalURL(_ value: String) -> String? {
        var value = value.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !value.isEmpty else {
            return nil
        }

        if value.hasPrefix("https://") {
            value = "wss://" + value.dropFirst("https://".count)
        } else if value.hasPrefix("http://") {
            value = "ws://" + value.dropFirst("http://".count)
        }

        guard value.hasPrefix("ws://") || value.hasPrefix("wss://") else {
            return nil
        }

        guard var components = URLComponents(string: value),
              let host = components.host,
              !host.isEmpty else {
            return nil
        }

        let path = components.path.trimmingCharacters(
            in: CharacterSet(charactersIn: "/")
        )
        if path.isEmpty {
            components.path = "/signal"
        } else if path != "signal" {
            components.path = "/\(path)/signal"
        }

        return components.string
    }

    private func extractErrorMessage(from data: Data) -> String {
        guard
            let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any],
            let message = object["error"] as? String
        else {
            return "The session service returned an error."
        }

        return message
    }

    enum HostError: LocalizedError {
        case invalidServiceURL
        case invalidResponse
        case invalidPassword
        case server(String)

        var errorDescription: String? {
            switch self {
            case .invalidServiceURL:
                return "Invalid code-service URL."
            case .invalidResponse:
                return "The session service returned an invalid response."
            case .invalidPassword:
                return "Room passwords must contain at least 4 characters."
            case .server(let message):
                return message
            }
        }
    }
}
