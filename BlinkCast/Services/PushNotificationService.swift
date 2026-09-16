import Foundation
import Combine
import UserNotifications
#if os(iOS)
import UIKit
#endif

@MainActor
final class PushNotificationService: ObservableObject {
    static let shared = PushNotificationService()

    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published var deviceToken: String?

    private let defaultServiceURL = "https://blinkcast-signaling.jaydenrmaine.workers.dev"

    private init() {
        #if os(iOS)
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            authorizationStatus = settings.authorizationStatus
        }
        #endif
    }

    func requestAuthorization() async -> Bool {
        #if os(iOS)
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            authorizationStatus = settings.authorizationStatus
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
            return granted
        } catch {
            return false
        }
        #else
        return false
        #endif
    }

    func updateDeviceToken(_ token: Data) {
        let value = token.map { String(format: "%02x", $0) }.joined()
        deviceToken = value
        UserDefaults.standard.set(value, forKey: "blinkcast.apns.deviceToken")
    }

    func loadStoredToken() {
        deviceToken = UserDefaults.standard.string(forKey: "blinkcast.apns.deviceToken")
    }

    func registerDeviceTokenWithBackend(roomID: String? = nil) async {
        guard let deviceToken else { return }

        let payload: [String: Any] = [
            "deviceToken": deviceToken,
            "platform": "ios",
            "roomId": roomID ?? "",
            "registeredAt": ISO8601DateFormatter().string(from: Date())
        ]

        guard let url = URL(string: "\(defaultServiceURL)/push/register") else {
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode >= 200,
               httpResponse.statusCode < 300 {
                NSLog("BlinkCast push token registered successfully")
            }
        } catch {
            NSLog("BlinkCast push registration failed: \(error.localizedDescription)")
        }
    }
}
