import Foundation
import CryptoKit

enum SessionSecurityBinding {
    static let expirySeconds: TimeInterval = 900

    static func generateNonce() -> String {
        UUID().uuidString.lowercased()
    }

    static func expiryDate() -> Date {
        Date().addingTimeInterval(expirySeconds)
    }

    static func signature(roomID: String, clientID: String, nonce: String, expiresAt: Date) -> String {
        let input = "\(roomID)|\(clientID)|\(nonce)|\(Int(expiresAt.timeIntervalSince1970))"
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    static func isValid(
        roomID: String,
        clientID: String,
        nonce: String,
        signatureToCheck: String,
        expiresAt: Date
    ) -> Bool {
        let expected = signature(
            roomID: roomID,
            clientID: clientID,
            nonce: nonce,
            expiresAt: expiresAt
        )
        return expected == signatureToCheck && expiresAt.timeIntervalSinceNow > 0
    }
}
