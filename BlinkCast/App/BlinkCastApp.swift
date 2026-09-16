import SwiftUI
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UIKit
#endif

@main
struct BlinkCastApp: App {
    @AppStorage("accentTheme")
    private var accentTheme = AccentTheme.blue.rawValue

    @AppStorage("appearance")
    private var appearance = "system"

    #if os(iOS)
    @UIApplicationDelegateAdaptor(BlinkCastAppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()

                #if os(macOS)
                MacWindowConfigurator()
                    .frame(width: 0, height: 0)
                #endif
            }
            .tint(
                AccentTheme.color(
                    for: accentTheme
                )
            )
            .preferredColorScheme(
                preferredColorScheme
            )
            .task {
                PushNotificationService.shared.loadStoredToken()
                #if os(iOS)
                await PushNotificationService.shared.requestAuthorization()
                #endif
            }
        }

        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        #endif
    }

    private var preferredColorScheme: ColorScheme? {
        switch appearance {
        case "light":
            return .light
        case "dark":
            return .dark
        default:
            return nil
        }
    }
}