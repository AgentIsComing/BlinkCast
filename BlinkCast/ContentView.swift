import SwiftUI

#if os(macOS)
import AppKit
#endif

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding")
    private var hasCompletedOnboarding = false

    var body: some View {
        if hasCompletedOnboarding {
            MainAppView()
        } else {
            OnboardingView()
        }
    }
}

struct MainAppView: View {
    enum Destination: String, CaseIterable, Identifiable {
        case home
        case host
        case join
        case settings

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .home:
                return "Home"
            case .host:
                return "Host"
            case .join:
                return "Join"
            case .settings:
                return "Settings"
            }
        }

        var icon: String {
            switch self {
            case .home:
                return "house.fill"

            case .host:
                return "rectangle.inset.filled.and.person.filled"

            case .join:
                return "play.rectangle.fill"

            case .settings:
                return "gearshape.fill"
            }
        }
    }

    @State private var selection: Destination? = .home

    var body: some View {
        VStack(spacing: 0) {
            customTitleBar

            NavigationSplitView {
                sidebar
            } detail: {
                detailContent
            }
            .navigationSplitViewStyle(.balanced)
        }
        .background(BlinkBackground())
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - Custom Title Bar

    private var customTitleBar: some View {
        HStack(spacing: 12) {
            #if os(macOS)
            Color.clear
                .frame(width: 74)
            #endif

            HStack(spacing: 9) {
                BlinkIconBadge(
                    systemImage: "bolt.horizontal.fill",
                    size: 30
                )

                Text("BlinkCast")
                    .font(.system(
                        size: 14,
                        weight: .semibold,
                        design: .rounded
                    ))
            }

            Spacer()

            Text(selection?.title ?? "Home")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            Spacer()

            BlinkStatusPill(
                text: "Ready",
                systemImage: "checkmark.circle.fill",
                tint: .green
            )

            #if os(macOS)
            Button {
                (NSApp.keyWindow ?? NSApp.windows.first)?.toggleFullScreen(nil)
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .help("Toggle Full Screen")
            #endif
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background {
            LinearGradient(
                colors: [
                    Color(red: 0.045, green: 0.052, blue: 0.082),
                    Color(red: 0.030, green: 0.035, blue: 0.060)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        ZStack {
            BlinkSidebarBackground()

            VStack(spacing: 0) {
                sidebarBrand

                List(
                    Destination.allCases,
                    selection: $selection
                ) { destination in
                    Label(
                        destination.title,
                        systemImage: destination.icon
                    )
                    .font(.body.weight(.semibold))
                    .padding(.vertical, 7)
                    .tag(destination)
                }
                .scrollContentBackground(.hidden)
                .listStyle(.sidebar)

                Spacer()

                sidebarFooter
            }
        }
        .navigationSplitViewColumnWidth(
            min: 190,
            ideal: 220,
            max: 250
        )
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailContent: some View {
        ZStack {
            BlinkBackground()

            switch selection ?? .home {
            case .home:
                HomeView(
                    openHost: {
                        selection = .host
                    },
                    openJoin: {
                        selection = .join
                    }
                )

            case .host:
                HostView()

            case .join:
                JoinView()

            case .settings:
                SettingsView()
            }
        }
    }

    // MARK: - Sidebar Brand

    private var sidebarBrand: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(
                    cornerRadius: 14,
                    style: .continuous
                )
                .fill(
                    LinearGradient(
                        colors: [
                            Color.accentColor,
                            Color.purple.opacity(0.85)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(
                    width: 42,
                    height: 42
                )

                Image(
                    systemName: "bolt.horizontal.fill"
                )
                .foregroundStyle(.white)
                .font(
                    .system(
                        size: 19,
                        weight: .bold
                    )
                )
            }

            VStack(
                alignment: .leading,
                spacing: 2
            ) {
                Text("BlinkCast")
                    .font(.headline)

                Text("Instant sharing")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    // MARK: - Sidebar Footer

    private var sidebarFooter: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(.green)
                .frame(
                    width: 8,
                    height: 8
                )

            Text("Ready")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
}

#Preview {
    ContentView()
}