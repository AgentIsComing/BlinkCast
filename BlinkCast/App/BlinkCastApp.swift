import SwiftUI

@main
struct BlinkCastApp: App {
    @AppStorage("accentTheme")
    private var accentTheme = AccentTheme.blue.rawValue

    @AppStorage("appearance")
    private var appearance = "system"

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