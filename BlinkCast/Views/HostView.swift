import SwiftUI
@preconcurrency import WebRTC

#if os(macOS)
import AppKit
#endif

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

    @StateObject private var hostService = HostSessionService.shared
    @StateObject private var signalingService = SignalingService.shared
    @StateObject private var webRTCService = WebRTCService.shared

    @State private var sessionType: SessionType = .screenShare
    @State private var source: ShareSource = .entireScreen

    @State private var roomName = ""
    @State private var roomPassword = ""

    private let signalingURL =
        "wss://blinkcast-signaling.jaydenrmaine.workers.dev/signal"

    @State private var requireApproval = true
    @State private var allowRemoteControl = false

    @State private var shareSystemAudio = true
    @State private var shareMicrophone = false
    @State private var shareCamera = false
    @State private var quality: WebRTCService.Quality = .balanced

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
                    qualityPicker
                    mediaControls
                    sessionSecurity
                    advancedSettings
                    createButton
                    hostStatusView
                }
            }
            .padding(30)
            .frame(
                maxWidth: 1100,
                alignment: .leading
            )
        }
        .navigationTitle("Host")
        .onChange(of: signalingService.state) { _, _ in
            hostService.updateFromSignaling()
            webRTCService.signalingDidUpdate()

            if hostService.state == .ready {
                sessionCode = hostService.sessionCode

                withAnimation(
                    .spring(
                        response: 0.35,
                        dampingFraction: 0.84
                    )
                ) {
                    isHosting = true
                }
            }
        }
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
                    ForEach(SessionType.allCases) { type in
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
                subtitle: "You can change this later while the session is live."
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
                ForEach(ShareSource.allCases) { item in
                    sourceButton(item)
                }
            }
        }
    }

    private func sourceButton(_ item: ShareSource) -> some View {
        Button {
            withAnimation(
                .spring(
                    response: 0.28,
                    dampingFraction: 0.82
                )
            ) {
                source = item
                #if os(macOS)
                webRTCService.setCaptureSource(
                    captureSource(for: item)
                )
                #endif
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
                            systemImage: "checkmark.circle.fill"
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
            BlinkSectionHeader(title: "Media")

            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(minimum: 220),
                        spacing: 14
                    )
                ],
                spacing: 14
            ) {
                mediaToggle(
                    title: "System Audio",
                    icon: "speaker.wave.2.fill",
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

    private var qualityPicker: some View {
        BlinkGlassCard {
            VStack(alignment: .leading, spacing: 14) {
                BlinkSectionHeader(
                    title: "Stream Quality",
                    subtitle: "Choose the tradeoff between detail, bandwidth, and battery."
                )

                Picker("Quality", selection: $quality) {
                    Text("Low").tag(WebRTCService.Quality.low)
                    Text("Balanced").tag(WebRTCService.Quality.balanced)
                    Text("High").tag(WebRTCService.Quality.high)
                }
                .pickerStyle(.segmented)
                .onChange(of: quality) { _, value in
                    webRTCService.setQuality(value)
                }
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

                Toggle("", isOn: value)
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
                    subtitle: "Share the five-digit code with the person joining this session."
                )

                Divider()

                TextField(
                    "Room name (optional)",
                    text: $roomName
                )
                .textFieldStyle(.roundedBorder)

                SecureField(
                    "Room password (optional, 4+ characters)",
                    text: $roomPassword
                )
                .textFieldStyle(.roundedBorder)

                Text(
                    "A 5-digit join code is always created. Room name + password are published too when both are provided."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

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
            DisclosureGroup(isExpanded: $showAdvanced) {
                VStack(spacing: 14) {
                    Divider()
                        .padding(.vertical, 4)

                    settingRow("Resolution", "Adaptive")
                    settingRow("Frame Rate", "Adaptive")
                    settingRow("Bitrate", "Adaptive")
                    settingRow("Latency Mode", "Balanced")
                    settingRow("Encryption", "Enabled")
                }
                .padding(.top, 10)
            } label: {
                HStack {
                    BlinkIconBadge(
                        systemImage: "slider.horizontal.3",
                        size: 44
                    )

                    VStack(
                        alignment: .leading,
                        spacing: 3
                    ) {
                        Text("Advanced")
                            .font(.headline)

                        Text("Streaming and connection controls")
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

    private var capturePreparationTitle: String {
        #if os(macOS)
        return "Preparing Screen Capture"
        #else
        return "Preparing Camera"
        #endif
    }

    private var capturePreparationSubtitle: String {
        #if os(macOS)
        return "Screen Recording permission is required to publish video."
        #else
        return "Camera permission is required to publish video."
        #endif
    }

    #if os(macOS)
    private func captureSource(
        for source: ShareSource
    ) -> ScreenCaptureService.Source {
        switch source {
        case .entireScreen:
            return .entireScreen
        case .monitor:
            return .monitor
        case .window:
            return .window
        case .application:
            return .application
        }
    }
    #endif

    private var createButton: some View {
        Button {
            Task {
                await startSession()
            }
        } label: {
            Label(
                startButtonText,
                systemImage: "dot.radiowaves.left.and.right"
            )
        }
        .buttonStyle(BlinkPrimaryButtonStyle())
        .frame(maxWidth: 520)
        .disabled(isStarting)
    }

    @ViewBuilder
    private var hostStatusView: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch hostService.state {
            case .idle:
                EmptyView()

            case .publishing:
                hostStatusRow(
                    text: "Publishing join code...",
                    icon: "number.circle.fill",
                    tint: .orange
                )

            case .connecting:
                hostStatusRow(
                    text: "Connecting host to signaling...",
                    icon: "antenna.radiowaves.left.and.right",
                    tint: .orange
                )

            case .ready:
                hostStatusRow(
                    text: "Host signaling is ready",
                    icon: "checkmark.circle.fill",
                    tint: .green
                )

            case .failed(let message):
                hostStatusRow(
                    text: message,
                    icon: "exclamationmark.triangle.fill",
                    tint: .red
                )

                #if os(macOS)
                if message.localizedCaseInsensitiveContains("Screen Recording") {
                    Button {
                        NSWorkspace.shared.open(
                            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
                        )
                    } label: {
                        Label(
                            "Open Screen Recording Settings",
                            systemImage: "gearshape.fill"
                        )
                    }
                    .buttonStyle(BlinkSecondaryButtonStyle())
                }
                #endif
            }
        }
    }

    private func hostStatusRow(
        text: String,
        icon: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(tint)

            Text(text)
                .font(.caption)
                .foregroundStyle(tint)
        }
    }

    private var startButtonText: String {
        switch hostService.state {
        case .publishing:
            return "Publishing Session..."
        case .connecting:
            return "Connecting..."
        default:
            return "Start BlinkCast Session"
        }
    }

    private var isStarting: Bool {
        switch hostService.state {
        case .publishing, .connecting:
            return true
        default:
            return false
        }
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

                Text("Your signaling session is ready for viewers.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            BlinkStatusPill(
                text: "Live",
                systemImage: "dot.radiowaves.left.and.right",
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
            .aspectRatio(16 / 9, contentMode: .fit)

            if let track = webRTCService.localVideoTrack {
                BlinkRemoteVideoView(track: track)
            } else {
                VStack(spacing: 14) {
                    Image(
                        systemName: "rectangle.inset.filled.and.person.filled"
                    )
                    .font(.system(size: 50))

                    Text(capturePreparationTitle)
                        .font(.title2.bold())

                    Text(capturePreparationSubtitle)
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.white)
            }
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
                    .adaptive(minimum: 130),
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
                icon: "rectangle.on.rectangle"
            )
            controlButton(
                title: webRTCService.isSharingPaused ? "Resume" : "Pause",
                icon: webRTCService.isSharingPaused
                    ? "play.fill"
                    : "pause.fill"
            )
        }
    }

    private func controlButton(
        title: String,
        icon: String
    ) -> some View {
        Button {
            handleLiveControl(title: title)
        } label: {
            Label(title, systemImage: icon)
        }
        .buttonStyle(BlinkSecondaryButtonStyle())
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
                            text: viewerCount > 0 ? "Connected" : "Waiting",
                            systemImage: viewerCount > 0
                                ? "checkmark.circle.fill"
                                : "clock.fill",
                            tint: viewerCount > 0 ? .green : .orange
                        )

                        Spacer()

                        Text("Advanced Stats")
                            .font(.headline)
                    }

                    Divider()

                    settingRow("Signaling", "Connected")
                    settingRow("WebRTC", webRTCService.peerConnectionState)
                    settingRow("ICE", webRTCService.iceConnectionState)
                    settingRow("Room", hostService.activeRoomID)
                    settingRow("Latency", "-- ms")
                    settingRow("Resolution", "Adaptive")
                    settingRow("FPS", "Adaptive")
                    settingRow("Bitrate", "Adaptive")
                }
            }

            Button(role: .destructive) {
                endSession()
            } label: {
                Label(
                    "End Session",
                    systemImage: "stop.circle.fill"
                )
            }
            .buttonStyle(BlinkPrimaryButtonStyle())
            .tint(.red)
            .frame(maxWidth: 420)
        }
    }

    private func startSession() async {
        viewerCount = 0
        sessionCode = "-----"
        webRTCService.setMediaOptions(
            publishMicrophone: shareMicrophone,
            publishCamera: shareCamera
        )
        webRTCService.setQuality(quality)

        signalingService.onViewerJoined = {
            viewerCount += 1
        }

        let started = await hostService.startSession(
            signalURL: signalingURL,
            requestedRoomID: roomName,
            password: roomPassword
        )

        if !started {
            return
        }

        sessionCode = hostService.sessionCode
    }

    private func endSession() {
        webRTCService.stop()
        hostService.endSession()
        viewerCount = 0
        sessionCode = "-----"

        withAnimation {
            isHosting = false
        }
    }

    private func handleLiveControl(title: String) {
        switch title {
        case "Audio":
            shareSystemAudio.toggle()
        case "Mic":
            shareMicrophone.toggle()
        case "Camera":
            shareCamera.toggle()
        case "Pause", "Resume":
            webRTCService.setSharingPaused(
                !webRTCService.isSharingPaused
            )
        default:
            break
        }
    }
}

#Preview {
    HostView()
}
