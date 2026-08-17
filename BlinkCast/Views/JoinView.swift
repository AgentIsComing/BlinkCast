import SwiftUI

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

    @State private var method: JoinMethod = .code
    @State private var joinCode = ""
    @State private var roomName = ""
    @State private var roomPassword = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                Spacer(minLength: 30)

                header

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
            .padding(30)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Join")
        .onChange(of: signalingService.state) { _, _ in
            joinService.updateFromSignaling()
        }
        .onChange(of: method) { _, _ in
            if !isConnected && !isBusy {
                joinService.resetJoinState()
            }
        }
    }

    private var header: some View {
        VStack(spacing: 16) {
            BlinkIconBadge(
                systemImage: "play.rectangle.fill",
                size: 78
            )

            VStack(spacing: 7) {
                Text("Join a Session")
                    .font(
                        .system(
                            size: 38,
                            weight: .bold,
                            design: .rounded
                        )
                    )

                Text("Connect to another BlinkCast device.")
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

            SecureField(
                "Password",
                text: $roomPassword
            )
            .textFieldStyle(.roundedBorder)

            Button {
                Task {
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

    private var disconnectButton: some View {
        Button {
            joinService.leaveSession()
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
            statusRow(
                text: "Signaling connected to host",
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
            return "Connected"
        case .waitingForHost:
            return "Waiting for Host"
        default:
            return method == .code ? "Join Session" : "Join Room"
        }
    }

    private var joinButtonIcon: String {
        switch joinService.joinState {
        case .connected:
            return "checkmark.circle.fill"
        case .waitingForHost:
            return "clock.fill"
        default:
            return "arrow.right.circle.fill"
        }
    }
}

#Preview {
    JoinView()
}
