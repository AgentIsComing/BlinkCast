import SwiftUI

struct SettingsView: View {
    @AppStorage("accentTheme")
    private var accentTheme =
        AccentTheme.blue.rawValue

    @AppStorage("appearance")
    private var appearance = "system"

    @AppStorage("hasCompletedOnboarding")
    private var hasCompletedOnboarding = true

    @AppStorage("askBeforeReconnect")
    private var askBeforeReconnect = true

    @AppStorage("warnSessionContinues")
    private var warnSessionContinues = true

    @AppStorage("chatEnabled")
    private var chatEnabled = true

    @AppStorage("blinkcast.receiveAudio")
    private var receiveAudio = false

    @AppStorage("blinkcast.iceServerURLs")
    private var iceServerURLs = ""

    @AppStorage("blinkcast.iceServerUsername")
    private var iceServerUsername = ""

    @AppStorage("blinkcast.iceServerCredential")
    private var iceServerCredential = ""

    var body: some View {
        ScrollView {
            VStack(
                alignment: .leading,
                spacing: 26
            ) {
                header

                appearanceCard

                sessionsCard

                streamingCard

                networkCard

                accountCard

                helpCard
            }
            .padding(30)
            .frame(
                maxWidth: 900,
                alignment: .leading
            )
        }
        .navigationTitle("Settings")
    }

    private var header: some View {
        VStack(
            alignment: .leading,
            spacing: 7
        ) {
            Text("Settings")
                .font(
                    .system(
                        size: 38,
                        weight: .bold,
                        design: .rounded
                    )
                )

            Text(
                "Make BlinkCast work the way you want."
            )
            .font(.title3)
            .foregroundStyle(.secondary)
        }
    }

    private var appearanceCard: some View {
        BlinkGlassCard {
            VStack(
                alignment: .leading,
                spacing: 20
            ) {
                BlinkSectionHeader(
                    title: "Appearance"
                )

                Picker(
                    "Appearance",
                    selection: $appearance
                ) {
                    Text("System")
                        .tag("system")

                    Text("Light")
                        .tag("light")

                    Text("Dark")
                        .tag("dark")
                }
                .pickerStyle(.segmented)

                Divider()

                Text("Accent Color")
                    .font(.headline)

                LazyVGrid(
                    columns: [
                        GridItem(
                            .adaptive(
                                minimum: 52,
                                maximum: 72
                            ),
                            spacing: 12
                        )
                    ],
                    spacing: 12
                ) {
                    ForEach(
                        AccentTheme.allCases
                    ) { theme in
                        Button {
                            withAnimation {
                                accentTheme =
                                    theme.rawValue
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(theme.color)
                                    .frame(
                                        width: 42,
                                        height: 42
                                    )

                                if accentTheme ==
                                    theme.rawValue {
                                    Image(
                                        systemName:
                                            "checkmark"
                                    )
                                    .font(
                                        .headline.bold()
                                    )
                                    .foregroundStyle(
                                        .white
                                    )
                                }
                            }
                            .frame(
                                maxWidth: .infinity
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var sessionsCard: some View {
        BlinkGlassCard {
            VStack(
                alignment: .leading,
                spacing: 18
            ) {
                BlinkSectionHeader(
                    title: "Sessions"
                )

                Toggle(
                    "Ask before reconnecting",
                    isOn: $askBeforeReconnect
                )

                Toggle(
                    "Warn when closing an active session",
                    isOn:
                        $warnSessionContinues
                )

                Toggle(
                    "Enable session chat",
                    isOn: $chatEnabled
                )

                Toggle(
                    "Receive shared audio",
                    isOn: $receiveAudio
                )
            }
        }
    }

    private var streamingCard: some View {
        BlinkGlassCard {
            VStack(
                spacing: 16
            ) {
                HStack {
                    BlinkSectionHeader(
                        title: "Streaming"
                    )

                    Spacer()

                    BlinkStatusPill(
                        text: "Adaptive",
                        systemImage:
                            "waveform.path.ecg"
                    )
                }

                Divider()

                settingsRow(
                    "Quality",
                    "Adaptive"
                )

                settingsRow(
                    "Resolution",
                    "Adaptive"
                )

                settingsRow(
                    "Frame Rate",
                    "Adaptive"
                )

                settingsRow(
                    "Latency",
                    "Balanced"
                )

                settingsRow(
                    "Encryption",
                    "Enabled"
                )
            }
        }
    }

    private var accountCard: some View {
        BlinkGlassCard {
            VStack(
                alignment: .leading,
                spacing: 16
            ) {
                HStack(spacing: 14) {
                    BlinkIconBadge(
                        systemImage:
                            "person.crop.circle.fill",
                        size: 52
                    )

                    VStack(
                        alignment: .leading,
                        spacing: 4
                    ) {
                        Text("BlinkCast Account")
                            .font(.headline)

                        Text(
                            "Optional"
                        )
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )
                    }
                }

                Text(
                    "Use BlinkCast without an account, or sign in later for friends, favorites, recent sessions, and device syncing."
                )
                .foregroundStyle(.secondary)

                Button {
                    print("Account")
                } label: {
                    Label(
                        "Sign In or Create Account",
                        systemImage:
                            "person.badge.plus"
                    )
                }
                .buttonStyle(
                    BlinkSecondaryButtonStyle()
                )
            }
        }
    }

    private var networkCard: some View {
        BlinkGlassCard {
            VStack(alignment: .leading, spacing: 16) {
                BlinkSectionHeader(
                    title: "Network",
                    subtitle: "Use your own STUN/TURN service for production sessions."
                )

                TextField(
                    "ICE server URLs, comma separated",
                    text: $iceServerURLs
                )
                .textFieldStyle(.roundedBorder)

                TextField(
                    "TURN username",
                    text: $iceServerUsername
                )
                .textFieldStyle(.roundedBorder)

                SecureField(
                    "TURN credential",
                    text: $iceServerCredential
                )
                .textFieldStyle(.roundedBorder)

                Text(
                    iceServerURLs.isEmpty
                        ? "The built-in public demo servers are currently in use."
                        : "Custom ICE servers will be used for new connections."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var helpCard: some View {
        BlinkGlassCard {
            VStack(
                alignment: .leading,
                spacing: 16
            ) {
                BlinkSectionHeader(
                    title: "Help & About"
                )

                Button {
                    hasCompletedOnboarding =
                        false
                } label: {
                    Label(
                        "Show Tutorial Again",
                        systemImage:
                            "questionmark.circle"
                    )
                }
                .buttonStyle(
                    BlinkSecondaryButtonStyle()
                )

                Divider()

                settingsRow(
                    "App",
                    "BlinkCast"
                )

                settingsRow(
                    "Platforms",
                    "Mac, iPhone & iPad"
                )
            }
        }
    }

    private func settingsRow(
        _ title: String,
        _ value: String
    ) -> some View {
        HStack {
            Text(title)

            Spacer()

            Text(value)
                .foregroundStyle(
                    .secondary
                )
        }
    }
}

#Preview {
    SettingsView()
}