import SwiftUI
@preconcurrency import WebRTC

struct JoinView: View {
    enum JoinMethod: String, CaseIterable, Identifiable {
        case code = "Join Code"
        case room = "Room"

        var id: String {
            rawValue
        }
    }

    @StateObject private var joinService = JoinCodeService.shared
    @StateObject private var signalingService = SignalingService.shared
    @StateObject private var webRTCService = WebRTCService.shared

    @State private var method: JoinMethod = .code
    @State private var joinCode = ""
    @State private var roomName = ""
    @State private var roomPassword = ""
    @State private var isStreamFullscreen = false
    @State private var remoteVideoAspectRatio: CGFloat = 16 / 9

    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                Spacer(minLength: 30)

                header

                if let track = webRTCService.remoteVideoTrack {
                    videoCard(track: track)
                } else {
                    joinCard
                }
            }
            .padding(30)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Join")
        .onChange(of: signalingService.state) { _, _ in
            joinService.updateFromSignaling()
            webRTCService.signalingDidUpdate()
        }
        .onChange(of: method) { _, _ in
            if !isConnected && !isBusy {
                joinService.resetJoinState()
            }
        }
        .onDisappear {
            if signalingService.currentRole == .viewer,
               !isConnected {
                webRTCService.stop()
            }
        }
        .overlay {
            if isStreamFullscreen,
               let track = webRTCService.remoteVideoTrack {
                BlinkFullscreenVideoView(
                    track: track,
                    dismiss: { isStreamFullscreen = false }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .zIndex(10)
            }
        }
        #if os(macOS)
        .onExitCommand {
            if isStreamFullscreen {
                isStreamFullscreen = false
            }
        }
        #endif
    }

    private var joinCard: some View {
        BlinkGlassCard {
            VStack(spacing: 22) {
                Picker(
                    "Join Method",
                    selection: $method
                ) {
                    ForEach(JoinMethod.allCases) { item in
                        Text(item.rawValue)
                            .tag(item)
                    }
                }
                .pickerStyle(.segmented)

                if method == .code {
                    codeJoin
                } else {
                    roomJoin
                }
            }
        }
        .frame(maxWidth: 520)
    }

    private var header: some View {
        VStack(spacing: 16) {
            BlinkIconBadge(
                systemImage: "play.rectangle.fill",
                size: 78
            )

            VStack(spacing: 7) {
                Text(webRTCService.remoteVideoTrack == nil ? "Join a Session" : "BlinkCast Live")
                    .font(
                        .system(
                            size: 38,
                            weight: .bold,
                            design: .rounded
                        )
                    )

                Text(
                    webRTCService.remoteVideoTrack == nil
                        ? "Connect to another BlinkCast device."
                        : "Streaming from the connected host."
                )
                .font(.title3)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var codeJoin: some View {
        VStack(spacing: 20) {
            Text("Enter the 5-digit code")
                .font(.headline)

            TextField(
                "00000",
                text: $joinCode
            )
            .textFieldStyle(.plain)
            .font(
                .system(
                    size: 44,
                    weight: .bold,
                    design: .rounded
                )
            )
            .multilineTextAlignment(.center)
            .padding(.vertical, 16)
            .padding(.horizontal, 20)
            .background(
                Color.primary.opacity(0.05)
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
                .stroke(
                    Color.primary.opacity(0.08),
                    lineWidth: 1
                )
            }
            .onChange(of: joinCode) { _, value in
                joinCode = String(
                    value.filter(\.isNumber).prefix(5)
                )
            }

            Button {
                Task {
                    webRTCService.stop()
                    await joinService.joinCode(joinCode)
                }
            } label: {
                Label(
                    joinButtonText,
                    systemImage: joinButtonIcon
                )
            }
            .buttonStyle(BlinkPrimaryButtonStyle())
            .disabled(joinCode.count != 5 || isBusy || isConnected)
            .opacity(
                joinCode.count == 5 && !isBusy
                    ? 1
                    : 0.55
            )

            statusView

            if isConnected {
                disconnectButton
            }

            Text(
                "The code is resolved through BlinkCast's shared code service, then this device joins the same signaling room as the Windows host."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
    }

    private var roomJoin: some View {
        VStack(spacing: 18) {
            TextField(
                "Room ID",
                text: $roomName
            )
            .textFieldStyle(.roundedBorder)
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            #endif

            SecureField(
                "Password",
                text: $roomPassword
            )
            .textFieldStyle(.roundedBorder)

            Button {
                Task {
                    webRTCService.stop()
                    await joinService.joinRoom(
                        name: roomName,
                        password: roomPassword
                    )
                }
            } label: {
                Label(
                    joinButtonText,
                    systemImage: joinButtonIcon
                )
            }
            .buttonStyle(BlinkPrimaryButtonStyle())
            .disabled(
                roomName.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty ||
                roomPassword.isEmpty ||
                isBusy ||
                isConnected
            )
            .opacity(
                roomName.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty || roomPassword.isEmpty
                    ? 0.55
                    : 1
            )

            statusView

            if isConnected {
                disconnectButton
            }
        }
    }

    private func videoCard(track: RTCVideoTrack) -> some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(
                    cornerRadius: 24,
                    style: .continuous
                )
                .fill(Color.black)

                BlinkRemoteVideoView(track: track) { size in
                    guard size.width > 0, size.height > 0 else { return }
                    remoteVideoAspectRatio = size.width / size.height
                }
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 24,
                            style: .continuous
                        )
                    )

                VStack {
                    HStack {
                        Spacer()

                        Button {
                            isStreamFullscreen = true
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                        .background(.black.opacity(0.55), in: Circle())
                        .help("Enter Full Screen Stream")
                        .padding(14)
                    }

                    Spacer()
                }
            }
            .aspectRatio(remoteVideoAspectRatio, contentMode: .fit)
            .frame(maxWidth: 1100)
            .overlay {
                RoundedRectangle(
                    cornerRadius: 24,
                    style: .continuous
                )
                .stroke(
                    Color.white.opacity(0.10),
                    lineWidth: 1
                )
            }

            HStack(spacing: 12) {
                BlinkStatusPill(
                    text: webRTCStatusText,
                    systemImage: webRTCStatusIcon,
                    tint: webRTCStatusTint
                )

                Button {
                    disconnect()
                } label: {
                    Label(
                        "Disconnect",
                        systemImage: "xmark.circle.fill"
                    )
                }
                .buttonStyle(BlinkSecondaryButtonStyle())
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("WebRTC: \(webRTCService.peerConnectionState)")
                Text("ICE: \(webRTCService.iceConnectionState)")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private var disconnectButton: some View {
        Button {
            disconnect()
        } label: {
            Label(
                "Disconnect",
                systemImage: "xmark.circle.fill"
            )
        }
        .buttonStyle(BlinkSecondaryButtonStyle())
    }

    @ViewBuilder
    private var statusView: some View {
        switch joinService.joinState {
        case .idle:
            EmptyView()

        case .resolving:
            statusRow(
                text: "Finding session...",
                icon: "magnifyingglass",
                tint: .secondary
            )

        case .connecting:
            statusRow(
                text: "Connecting to signaling...",
                icon: "antenna.radiowaves.left.and.right",
                tint: .orange
            )

        case .waitingForHost:
            statusRow(
                text: "Connected. Waiting for host...",
                icon: "clock.fill",
                tint: .orange
            )

        case .connected:
            switch webRTCService.state {
            case .idle, .preparing:
                statusRow(
                    text: "Preparing WebRTC...",
                    icon: "gearshape.2.fill",
                    tint: .orange
                )

            case .negotiating:
                statusRow(
                    text: "Negotiating video stream...",
                    icon: "arrow.triangle.2.circlepath",
                    tint: .orange
                )

            case .connected:
                statusRow(
                    text: "Video connected",
                    icon: "checkmark.circle.fill",
                    tint: .green
                )

            case .failed(let message):
                statusRow(
                    text: message,
                    icon: "exclamationmark.triangle.fill",
                    tint: .red
                )
            }

        case .failed(let message):
            statusRow(
                text: message,
                icon: "exclamationmark.triangle.fill",
                tint: .red
            )
        }
    }

    private func statusRow(
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
        .multilineTextAlignment(.center)
    }

    private func disconnect() {
        webRTCService.stop()
        joinService.leaveSession()
    }

    private var isBusy: Bool {
        switch joinService.joinState {
        case .resolving, .connecting:
            return true
        default:
            return false
        }
    }

    private var isConnected: Bool {
        switch joinService.joinState {
        case .connected, .waitingForHost:
            return true
        default:
            return false
        }
    }

    private var joinButtonText: String {
        switch joinService.joinState {
        case .resolving:
            return "Finding Session..."
        case .connecting:
            return "Connecting..."
        case .connected:
            switch webRTCService.state {
            case .connected:
                return "Streaming"
            default:
                return "Connecting Video..."
            }
        case .waitingForHost:
            return "Waiting for Host"
        default:
            return method == .code ? "Join Session" : "Join Room"
        }
    }

    private var joinButtonIcon: String {
        switch joinService.joinState {
        case .connected:
            return webRTCService.state == .connected
                ? "play.rectangle.fill"
                : "arrow.triangle.2.circlepath"
        case .waitingForHost:
            return "clock.fill"
        default:
            return "arrow.right.circle.fill"
        }
    }

    private var webRTCStatusText: String {
        switch webRTCService.state {
        case .connected:
            return "Connected"
        case .negotiating:
            return "Negotiating"
        case .preparing:
            return "Preparing"
        case .failed:
            return "Connection Error"
        case .idle:
            return "Idle"
        }
    }

    private var webRTCStatusIcon: String {
        switch webRTCService.state {
        case .connected:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        default:
            return "antenna.radiowaves.left.and.right"
        }
    }

    private var webRTCStatusTint: Color {
        switch webRTCService.state {
        case .connected:
            return .green
        case .failed:
            return .red
        default:
            return .orange
        }
    }
}

private struct BlinkFullscreenVideoView: View {
    let track: RTCVideoTrack
    let dismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            BlinkRemoteVideoView(track: track)
                .ignoresSafeArea()

            VStack {
                HStack {
                    Spacer()

                    Button(action: dismiss) {
                        Image(systemName: "xmark")
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(.black.opacity(0.6), in: Circle())
                    .help("Exit Full Screen Stream")
                    .padding(18)
                }

                Spacer()
            }
        }
    }
}

#Preview {
    JoinView()
}
