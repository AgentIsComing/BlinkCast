import SwiftUI

struct JoinView: View {
    enum JoinMethod:
        String,
        CaseIterable,
        Identifiable {

        case code = "Join Code"
        case room = "Room"

        var id: String {
            rawValue
        }
    }

    @StateObject private var joinService =
        JoinCodeService.shared

    @StateObject private var signalingService =
        SignalingService.shared

    @State private var method:
        JoinMethod = .room

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
                            ForEach(
                                JoinMethod
                                    .allCases
                            ) { item in
                                Text(
                                    item.rawValue
                                )
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
        .onChange(
            of: signalingService.state
        ) { _, _ in
            joinService
                .updateFromSignaling()
        }
    }

    private var header: some View {
        VStack(spacing: 16) {
            BlinkIconBadge(
                systemImage:
                    "play.rectangle.fill",
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

                Text(
                    "Connect to another BlinkCast device."
                )
                .font(.title3)
                .foregroundStyle(
                    .secondary
                )
            }
        }
    }

    private var codeJoin: some View {
        VStack(spacing: 20) {
            Text(
                "5-digit codes will be connected to the cross-platform service next."
            )
            .font(.headline)
            .multilineTextAlignment(
                .center
            )

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
            .multilineTextAlignment(
                .center
            )
            .padding(.vertical, 16)
            .padding(.horizontal, 20)
            .background(
                Color.primary
                    .opacity(0.05)
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
            )
            .onChange(
                of: joinCode
            ) { _, value in
                joinCode =
                    String(
                        value
                            .filter(
                                \.isNumber
                            )
                            .prefix(5)
                    )
            }

            Button {
            } label: {
                Label(
                    "Join Session",
                    systemImage:
                        "arrow.right.circle.fill"
                )
            }
            .buttonStyle(
                BlinkPrimaryButtonStyle()
            )
            .disabled(true)
            .opacity(0.55)
        }
    }

    private var roomJoin: some View {
        VStack(spacing: 18) {
            TextField(
                "Room ID",
                text: $roomName
            )
            .textFieldStyle(
                .roundedBorder
            )

            SecureField(
                "Password",
                text: $roomPassword
            )
            .textFieldStyle(
                .roundedBorder
            )

            Button {
                Task {
                    await joinService
                        .joinRoom(
                            name:
                                roomName,
                            password:
                                roomPassword
                        )
                }
            } label: {
                Label(
                    joinButtonText,
                    systemImage:
                        joinButtonIcon
                )
            }
            .buttonStyle(
                BlinkPrimaryButtonStyle()
            )
            .disabled(
                roomName.isEmpty ||
                roomPassword.isEmpty ||
                isBusy
            )
            .opacity(
                roomName.isEmpty ||
                roomPassword.isEmpty
                    ? 0.55
                    : 1
            )

            statusView

            if isConnected {
                Button {
                    joinService
                        .leaveSession()
                } label: {
                    Label(
                        "Disconnect",
                        systemImage:
                            "xmark.circle.fill"
                    )
                }
                .buttonStyle(
                    BlinkSecondaryButtonStyle()
                )
            }
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch joinService.joinState {
        case .idle:
            EmptyView()

        case .resolving:
            statusRow(
                text:
                    "Finding Windows host...",
                icon:
                    "magnifyingglass",
                tint: .secondary
            )

        case .connecting:
            statusRow(
                text:
                    "Connecting to signaling...",
                icon:
                    "antenna.radiowaves.left.and.right",
                tint: .orange
            )

        case .waitingForHost:
            statusRow(
                text:
                    "Connected. Waiting for host...",
                icon:
                    "clock.fill",
                tint: .orange
            )

        case .connected:
            statusRow(
                text:
                    "Connected to host",
                icon:
                    "checkmark.circle.fill",
                tint: .green
            )

        case .failed(
            let message
        ):
            statusRow(
                text: message,
                icon:
                    "exclamationmark.triangle.fill",
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
            Image(
                systemName: icon
            )
            .foregroundStyle(tint)

            Text(text)
                .font(.caption)
                .foregroundStyle(tint)
        }
        .multilineTextAlignment(
            .center
        )
    }

    private var isBusy: Bool {
        switch joinService.joinState {
        case .resolving,
             .connecting:
            return true

        default:
            return false
        }
    }

    private var isConnected: Bool {
        switch joinService.joinState {
        case .connected,
             .waitingForHost:
            return true

        default:
            return false
        }
    }

    private var joinButtonText: String {
        switch joinService.joinState {
        case .resolving:
            return "Finding Room..."

        case .connecting:
            return "Connecting..."

        case .connected:
            return "Connected"

        case .waitingForHost:
            return "Waiting for Host"

        default:
            return "Join Room"
        }
    }

    private var joinButtonIcon: String {
        switch joinService.joinState {
        case .connected:
            return
                "checkmark.circle.fill"

        case .waitingForHost:
            return "clock.fill"

        default:
            return
                "arrow.right.circle.fill"
        }
    }
}

#Preview {
    JoinView()
}