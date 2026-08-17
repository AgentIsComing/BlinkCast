import SwiftUI

struct HomeView: View {
    let openHost: () -> Void
    let openJoin: () -> Void

    var body: some View {
        ScrollView {
            VStack(
                alignment: .leading,
                spacing: 30
            ) {
                BlinkHeroPanel(
                    title: "BlinkCast",
                    subtitle: "Share instantly. Stay connected."
                )

                quickActions

                activeSessions

                recentSessions
            }
            .padding(30)
            .frame(
                maxWidth: 1100,
                alignment: .leading
            )
        }
        .navigationTitle("Home")
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 14) {
            BlinkSectionHeader(
                title: "Quick Actions",
                subtitle: "Start sharing or connect to someone else."
            )

            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(
                            minimum: 280,
                            maximum: 500
                        ),
                        spacing: 18
                    )
                ],
                spacing: 18
            ) {
                actionCard(
                    icon: "rectangle.inset.filled.and.person.filled",
                    title: "New Session",
                    subtitle: "Choose what to share and start instantly.",
                    actionTitle: "Start",
                    action: openHost
                )

                actionCard(
                    icon: "play.rectangle.fill",
                    title: "Quick Join",
                    subtitle: "Enter a BlinkCast session code.",
                    actionTitle: "Join",
                    action: openJoin
                )
            }
        }
    }

    private func actionCard(
        icon: String,
        title: String,
        subtitle: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        BlinkHoverCard {
            BlinkGlassCard {
                VStack(
                    alignment: .leading,
                    spacing: 18
                ) {
                    HStack {
                        BlinkIconBadge(
                            systemImage: icon,
                            size: 58
                        )

                        Spacer()

                        Image(systemName: "arrow.up.right")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(.title2.bold())

                        Text(subtitle)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer(minLength: 6)

                    Button(action: action) {
                        HStack(spacing: 6) {
                            Text(actionTitle)

                            Image(systemName: "chevron.right")
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                }
                .frame(
                    maxWidth: .infinity,
                    minHeight: 175,
                    alignment: .leading
                )
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            action()
        }
    }

    private var activeSessions: some View {
        VStack(
            alignment: .leading,
            spacing: 14
        ) {
            BlinkSectionHeader(
                title: "Active Sessions",
                subtitle: "Anything currently running will appear here."
            )

            BlinkGlassCard {
                HStack(spacing: 18) {
                    BlinkIconBadge(
                        systemImage: "dot.radiowaves.left.and.right",
                        size: 54
                    )

                    VStack(alignment: .leading, spacing: 5) {
                        Text("No Active Sessions")
                            .font(.headline)

                        Text(
                            "Start or join a session and it will appear here."
                        )
                        .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .frame(
                    maxWidth: .infinity,
                    minHeight: 90
                )
            }
        }
    }

    private var recentSessions: some View {
        VStack(
            alignment: .leading,
            spacing: 14
        ) {
            BlinkSectionHeader(
                title: "Recent Sessions",
                subtitle: "Reconnect quickly to previous devices and people."
            )

            BlinkGlassCard {
                HStack(spacing: 18) {
                    BlinkIconBadge(
                        systemImage: "clock.arrow.circlepath",
                        size: 54
                    )

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Nothing Here Yet")
                            .font(.headline)

                        Text(
                            "Your recent BlinkCast sessions will show up here."
                        )
                        .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .frame(
                    maxWidth: .infinity,
                    minHeight: 90
                )
            }
        }
    }
}

struct BlinkHoverCard<Content: View>: View {
    @State private var isHovering = false

    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .scaleEffect(isHovering ? 1.015 : 1)
            .shadow(
                color: Color.accentColor.opacity(isHovering ? 0.14 : 0),
                radius: isHovering ? 18 : 0,
                y: isHovering ? 8 : 0
            )
            .animation(
                .easeOut(duration: 0.16),
                value: isHovering
            )
            #if os(macOS)
            .onHover { hovering in
                isHovering = hovering
            }
            #endif
    }
}

#Preview {
    HomeView(
        openHost: {},
        openJoin: {}
    )
}