import SwiftUI

struct HostView: View {
    enum SessionType: String, CaseIterable, Identifiable {
        case screenShare = "Screen Share"
        case remoteControl = "Remote Control"

        var id: String {
            rawValue
        }
    }

    enum ShareSource: String, CaseIterable, Identifiable {
        case entireScreen = "Entire Screen"
        case monitor = "Monitor"
        case window = "Window"
        case application = "Application"

        var id: String {
            rawValue
        }

        var icon: String {
            switch self {
            case .entireScreen:
                return "rectangle.fill.on.rectangle.fill"

            case .monitor:
                return "display"

            case .window:
                return "macwindow"

            case .application:
                return "square.grid.2x2.fill"
            }
        }
    }

    @State private var sessionType: SessionType =
        .screenShare

    @State private var source: ShareSource =
        .entireScreen

    @State private var roomName = ""
    @State private var roomPassword = ""

    @State private var requireApproval = true
    @State private var allowRemoteControl = false

    @State private var shareSystemAudio = true
    @State private var shareMicrophone = false
    @State private var shareCamera = false

    @State private var showAdvanced = false
    @State private var isHosting = false

    @State private var viewerCount = 0
    @State private var sessionCode = "-----"

    var body: some View {
        ScrollView {
            VStack(
                alignment: .leading,
                spacing: 28
            ) {
                if isHosting {
                    liveHeader
                    livePreview
                    liveControls
                    liveInformation
                } else {
                    setupHeader
                    sessionTypePicker
                    sourcePicker
                    mediaControls
                    sessionSecurity
                    advancedSettings
                    createButton
                }
            }
            .padding(30)
            .frame(
                maxWidth: 1100,
                alignment: .leading
            )
        }
        .navigationTitle("Host")
    }

    private var setupHeader: some View {
        HStack {
            VStack(
                alignment: .leading,
                spacing: 7
            ) {
                Text("Create a Session")
                    .font(
                        .system(
                            size: 38,
                            weight: .bold,
                            design: .rounded
                        )
                    )

                Text(
                    "Choose what to share and BlinkCast will handle the rest."
                )
                .font(.title3)
                .foregroundStyle(.secondary)
            }

            Spacer()

            BlinkStatusPill(
                text: "Ready",
                systemImage: "bolt.fill"
            )
        }
    }

    private var sessionTypePicker: some View {
        BlinkGlassCard {
            VStack(
                alignment: .leading,
                spacing: 16
            ) {
                BlinkSectionHeader(
                    title: "Session Type"
                )

                Picker(
                    "Session Type",
                    selection: $sessionType
                ) {
                    ForEach(
                        SessionType.allCases
                    ) { type in
                        Text(type.rawValue)
                            .tag(type)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var sourcePicker: some View {
        VStack(
            alignment: .leading,
            spacing: 14
        ) {
            BlinkSectionHeader(
                title: "What do you want to share?",
                subtitle:
                    "You can change this later while the session is live."
            )

            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(
                            minimum: 190,
                            maximum: 300
                        ),
                        spacing: 15
                    )
                ],
                spacing: 15
            ) {
                ForEach(
                    ShareSource.allCases
                ) { item in
                    sourceButton(item)
                }
            }
        }
    }

    private func sourceButton(
        _ item: ShareSource
    ) -> some View {
        Button {
            withAnimation(
                .spring(
                    response: 0.28,
                    dampingFraction: 0.82
                )
            ) {
                source = item
            }
        } label: {
            BlinkGlassCard {
                VStack(spacing: 16) {
                    BlinkIconBadge(
                        systemImage: item.icon,
                        size: 62
                    )

                    Text(item.rawValue)
                        .font(.headline)

                    if source == item {
                        BlinkStatusPill(
                            text: "Selected",
                            systemImage:
                                "checkmark.circle.fill"
                        )
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    minHeight: 145
                )
            }
            .overlay {
                if source == item {
                    RoundedRectangle(
                        cornerRadius: 26,
                        style: .continuous
                    )
                    .stroke(
                        Color.accentColor,
                        lineWidth: 2
                    )
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var mediaControls: some View {
        VStack(
            alignment: .leading,
            spacing: 14
        ) {
            BlinkSectionHeader(
                title: "Media"
            )

            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(
                            minimum: 220
                        ),
                        spacing: 14
                    )
                ],
                spacing: 14
            ) {
                mediaToggle(
                    title: "System Audio",
                    icon:
                        "speaker.wave.2.fill",
                    value: $shareSystemAudio
                )

                mediaToggle(
                    title: "Microphone",
                    icon: "mic.fill",
                    value: $shareMicrophone
                )

                mediaToggle(
                    title: "Camera",
                    icon: "video.fill",
                    value: $shareCamera
                )
            }
        }
    }

    private func mediaToggle(
        title: String,
        icon: String,
        value: Binding<Bool>
    ) -> some View {
        BlinkGlassCard {
            HStack(spacing: 14) {
                BlinkIconBadge(
                    systemImage: icon,
                    size: 46
                )

                Text(title)
                    .font(.headline)

                Spacer()

                Toggle(
                    "",
                    isOn: value
                )
                .labelsHidden()
            }
        }
    }

    private var sessionSecurity: some View {
        BlinkGlassCard {
            VStack(
                alignment: .leading,
                spacing: 18
            ) {
                BlinkSectionHeader(
                    title: "Session Access",
                    subtitle:
                        "Control who can join and what they're allowed to do."
                )

                TextField(
                    "Room name (optional)",
                    text: $roomName
                )
                .textFieldStyle(.roundedBorder)

                SecureField(
                    "Password (optional)",
                    text: $roomPassword
                )
                .textFieldStyle(.roundedBorder)

                Divider()

                Toggle(
                    "Require approval before viewers join",
                    isOn: $requireApproval
                )

                Toggle(
                    "Allow remote control requests",
                    isOn: $allowRemoteControl
                )
            }
        }
    }

    private var advancedSettings: some View {
        BlinkGlassCard {
            DisclosureGroup(
                isExpanded: $showAdvanced
            ) {
                VStack(spacing: 14) {
                    Divider()
                        .padding(.vertical, 4)

                    settingRow(
                        "Resolution",
                        "Adaptive"
                    )

                    settingRow(
                        "Frame Rate",
                        "Adaptive"
                    )

                    settingRow(
                        "Bitrate",
                        "Adaptive"
                    )

                    settingRow(
                        "Latency Mode",
                        "Balanced"
                    )

                    settingRow(
                        "Encryption",
                        "Enabled"
                    )
                }
                .padding(.top, 10)
            } label: {
                HStack {
                    BlinkIconBadge(
                        systemImage:
                            "slider.horizontal.3",
                        size: 44
                    )

                    VStack(
                        alignment: .leading,
                        spacing: 3
                    ) {
                        Text("Advanced")
                            .font(.headline)

                        Text(
                            "Streaming and connection controls"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func settingRow(
        _ title: String,
        _ value: String
    ) -> some View {
        HStack {
            Text(title)

            Spacer()

            Text(value)
                .foregroundStyle(.secondary)
        }
    }

    private var createButton: some View {
        Button {
            startSession()
        } label: {
            Label(
                "Start BlinkCast Session",
                systemImage:
                    "dot.radiowaves.left.and.right"
            )
        }
        .buttonStyle(
            BlinkPrimaryButtonStyle()
        )
        .frame(maxWidth: 520)
    }

    private var liveHeader: some View {
        HStack {
            VStack(
                alignment: .leading,
                spacing: 7
            ) {
                Text("You're Live")
                    .font(
                        .system(
                            size: 38,
                            weight: .bold,
                            design: .rounded
                        )
                    )

                Text(
                    "Your screen is ready for viewers."
                )
                .font(.title3)
                .foregroundStyle(.secondary)
            }

            Spacer()

            BlinkStatusPill(
                text: "Live",
                systemImage:
                    "dot.radiowaves.left.and.right",
                tint: .green
            )
        }
    }

    private var livePreview: some View {
        ZStack {
            RoundedRectangle(
                cornerRadius: 28,
                style: .continuous
            )
            .fill(Color.black)
            .aspectRatio(
                16 / 9,
                contentMode: .fit
            )

            VStack(spacing: 14) {
                Image(
                    systemName:
                        "rectangle.inset.filled.and.person.filled"
                )
                .font(.system(size: 50))

                Text("Live Preview")
                    .font(.title2.bold())

                Text(
                    "Screen capture will appear here."
                )
                .foregroundStyle(.secondary)
            }
            .foregroundStyle(.white)
        }
        .overlay {
            RoundedRectangle(
                cornerRadius: 28,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(0.10),
                lineWidth: 1
            )
        }
        .shadow(
            color: .black.opacity(0.2),
            radius: 30,
            y: 16
        )
    }

    private var liveControls: some View {
        LazyVGrid(
            columns: [
                GridItem(
                    .adaptive(
                        minimum: 130
                    ),
                    spacing: 12
                )
            ],
            spacing: 12
        ) {
            controlButton(
                title: "Audio",
                icon: "speaker.wave.2.fill"
            )

            controlButton(
                title: "Mic",
                icon: "mic.fill"
            )

            controlButton(
                title: "Camera",
                icon: "video.fill"
            )

            controlButton(
                title: "Source",
                icon:
                    "rectangle.on.rectangle"
            )
        }
    }

    private func controlButton(
        title: String,
        icon: String
    ) -> some View {
        Button {
            handleLiveControl(
                title: title
            )
        } label: {
            Label(
                title,
                systemImage: icon
            )
        }
        .buttonStyle(
            BlinkSecondaryButtonStyle()
        )
    }

    private var liveInformation: some View {
        VStack(spacing: 18) {
            BlinkGlassCard {
                HStack {
                    VStack(
                        alignment: .leading,
                        spacing: 6
                    ) {
                        Text("Session Code")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(sessionCode)
                            .font(
                                .system(
                                    size: 38,
                                    weight: .bold,
                                    design: .rounded
                                )
                            )
                    }

                    Spacer()

                    VStack(
                        alignment: .trailing,
                        spacing: 6
                    ) {
                        Text("Viewers")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("\(viewerCount)")
                            .font(.title.bold())
                    }
                }
            }

            BlinkGlassCard {
                VStack(spacing: 14) {
                    HStack {
                        BlinkStatusPill(
                            text:
                                viewerCount > 0
                                ? "Connected"
                                : "Waiting",
                            systemImage:
                                viewerCount > 0
                                ? "checkmark.circle.fill"
                                : "clock.fill",
                            tint:
                                viewerCount > 0
                                ? .green
                                : .orange
                        )

                        Spacer()

                        Text("Advanced Stats")
                            .font(.headline)
                    }

                    Divider()

                    settingRow(
                        "Latency",
                        "-- ms"
                    )

                    settingRow(
                        "Resolution",
                        "Adaptive"
                    )

                    settingRow(
                        "FPS",
                        "Adaptive"
                    )

                    settingRow(
                        "Bitrate",
                        "Adaptive"
                    )
                }
            }

            Button(role: .destructive) {
                endSession()
            } label: {
                Label(
                    "End Session",
                    systemImage:
                        "stop.circle.fill"
                )
            }
            .buttonStyle(
                BlinkPrimaryButtonStyle()
            )
            .tint(.red)
            .frame(maxWidth: 420)
        }
    }

    private func startSession() {
        sessionCode =
            String(
                Int.random(
                    in: 10000...99999
                )
            )

        viewerCount = 0

        withAnimation(
            .spring(
                response: 0.35,
                dampingFraction: 0.84
            )
        ) {
            isHosting = true
        }
    }

    private func endSession() {
        viewerCount = 0
        sessionCode = "-----"

        withAnimation {
            isHosting = false
        }
    }

    private func handleLiveControl(
        title: String
    ) {
        switch title {
        case "Audio":
            shareSystemAudio.toggle()

        case "Mic":
            shareMicrophone.toggle()

        case "Camera":
            shareCamera.toggle()

        default:
            break
        }
    }
}

#Preview {
    HostView()
}