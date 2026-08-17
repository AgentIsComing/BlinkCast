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
    }

    @Published private(set) var joinState:
        JoinState = .idle

    @Published private(set) var joinedRoom:
        ResolvedRoom?

    private let signalingService =
        SignalingService.shared

    private let defaultCodeServiceURL =
        "https://live-screen-share-code-service.jaydenrmaine.workers.dev"

    private init() {
        signalingService.onBroadcastEnded = {
            [weak self] in

            self?.joinState =
                .failed(
                    "The host ended the session."
                )
        }
    }

    @discardableResult
    func joinRoom(
        name: String,
        password: String
    ) async -> Bool {
        let roomID =
            name.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !roomID.isEmpty else {
            joinState =
                .failed(
                    "Enter a Room ID."
                )

            return false
        }

        guard !password.isEmpty else {
            joinState =
                .failed(
                    "Enter the room password."
                )

            return false
        }

        joinState = .resolving

        do {
            let room =
                try await resolveRoom(
                    roomID: roomID,
                    password: password
                )

            joinedRoom = room

            joinState = .connecting

            signalingService.connect(
                signalURL:
                    room.signalURL,
                roomID:
                    room.roomID,
                role:
                    .viewer
            )

            return true
        } catch {
            joinState =
                .failed(
                    error.localizedDescription
                )

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
                joinState =
                    .failed(
                        "Disconnected from signaling."
                    )
            }

        case .connecting:
            joinState = .connecting

        case .connected:
            joinState = .connecting

        case .joined:
            joinState = .connected

        case .waitingForHost:
            joinState =
                .waitingForHost

        case .failed(let message):
            joinState =
                .failed(message)
        }
    }

    private func resolveRoom(
        roomID: String,
        password: String
    ) async throws -> ResolvedRoom {
        guard
            let url = URL(
                string:
                    "\(defaultCodeServiceURL)/resolve"
            )
        else {
            throw JoinError.invalidServiceURL
        }

        var request =
            URLRequest(url: url)

        request.httpMethod = "POST"

        request.setValue(
            "application/json",
            forHTTPHeaderField:
                "Content-Type"
        )

        let payload: [String: Any] = [
            "roomId": roomID,
            "password": password
        ]

        request.httpBody =
            try JSONSerialization.data(
                withJSONObject: payload
            )

        let (
            data,
            response
        ) =
            try await URLSession.shared.data(
                for: request
            )

        guard
            let httpResponse =
                response as?
                    HTTPURLResponse
        else {
            throw JoinError.invalidResponse
        }

        guard
            (200...299)
                .contains(
                    httpResponse.statusCode
                )
        else {
            let serverMessage =
                extractErrorMessage(
                    from: data
                )

            throw JoinError.server(
                serverMessage
            )
        }

        guard
            let object =
                try JSONSerialization.jsonObject(
                    with: data
                ) as? [String: Any],
            let wsURL =
                object[
                    "wsUrl"
                ] as? String,
            !wsURL.isEmpty
        else {
            throw JoinError.invalidResponse
        }

        return ResolvedRoom(
            roomID: roomID,
            signalURL: wsURL
        )
    }

    private func extractErrorMessage(
        from data: Data
    ) -> String {
        guard
            let object =
                try? JSONSerialization.jsonObject(
                    with: data
                ) as? [String: Any],
            let error =
                object[
                    "error"
                ] as? String
        else {
            return "Room could not be resolved."
        }

        return error
    }

    enum JoinError:
        LocalizedError {

        case invalidServiceURL
        case invalidResponse
        case server(String)

        var errorDescription: String? {
            switch self {
            case .invalidServiceURL:
                return
                    "Invalid code service URL."

            case .invalidResponse:
                return
                    "The room service returned an invalid response."

            case .server(let message):
                return message
            }
        }
    }
}