#if os(iOS)
import SwiftUI

struct MobileHomeView: View {
    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                MobileJoinView()
                    .navigationTitle("Join")
            }
            .tabItem {
                Label("Join", systemImage: "play.rectangle.fill")
            }
            .tag(0)

            NavigationStack {
                MobileHostView()
                    .navigationTitle("Host")
            }
            .tabItem {
                Label("Host", systemImage: "rectangle.inset.filled.and.person.filled")
            }
            .tag(1)
        }
        .tint(Color.accentColor)
    }
}

struct MobileJoinView: View {
    @StateObject private var joinService = JoinCodeService.shared
    @StateObject private var signalingService = SignalingService.shared

    @State private var joinCode = ""
    @State private var roomPassword = ""
    @State private var isRequestingPush = false
    @State private var isJoining = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 12)

            Image(systemName: "video.fill")
                .font(.system(size: 52))
                .foregroundStyle(Color.accentColor)

            Text("Join a BlinkCast room")
                .font(.title2.bold())

            TextField("Enter 5-digit code", text: $joinCode)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .onChange(of: joinCode) { _, newValue in
                    joinCode = String(newValue.filter { $0.isNumber }.prefix(5))
                }

            SecureField("Room password (optional)", text: $roomPassword)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)

            Button {
                Task {
                    isRequestingPush = true
                    _ = await PushNotificationService.shared.requestAuthorization()
                    isRequestingPush = false
                }
            } label: {
                Label(
                    isRequestingPush ? "Requesting access..." : "Enable notifications",
                    systemImage: "bell.fill"
                )
            }
            .buttonStyle(.borderedProminent)

            Button {
                Task {
                    isJoining = true
                    let success = await joinService.joinCode(joinCode, password: roomPassword)
                    if success {
                        await PushNotificationService.shared.registerDeviceTokenWithBackend(
                            roomID: signalingService.currentRoomID.isEmpty ? nil : signalingService.currentRoomID
                        )
                    }
                    isJoining = false
                }
            } label: {
                Label(
                    isJoining ? "Joining..." : "Join Session",
                    systemImage: "arrow.right"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(joinCode.count != 5 || isJoining)

            if case .failed(let message) = joinService.joinState {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            if case .waitingForHost = joinService.joinState {
                Text("Waiting for host approval...")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if case .connected = joinService.joinState {
                Text("Connected to signaling")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            Spacer()
        }
        .padding(24)
        .task {
            if let roomID = joinService.joinedRoom?.roomID, !roomID.isEmpty {
                await PushNotificationService.shared.registerDeviceTokenWithBackend(roomID: roomID)
            }
        }
    }
}

struct MobileHostView: View {
    @StateObject private var hostService = HostSessionService.shared
    @StateObject private var signalingService = SignalingService.shared
    @StateObject private var moderationService = ViewerModerationService.shared

    @State private var roomName = ""
    @State private var roomPassword = ""
    @State private var requireApproval = true
    @State private var isStarting = false

    private let signalingURL = "wss://blinkcast-signaling.jaydenrmaine.workers.dev/signal"

    var body: some View {
        VStack(spacing: 18) {
            Text("Start a room")
                .font(.title2.bold())

            Text("Launch a session and approve viewers before they can join the stream.")
                .foregroundStyle(.secondary)

            TextField("Room name (optional)", text: $roomName)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)

            SecureField("Password (optional)", text: $roomPassword)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)

            Toggle("Require viewer approval", isOn: $requireApproval)

            Button {
                Task {
                    isStarting = true
                    _ = await PushNotificationService.shared.requestAuthorization()
                    let started = await hostService.startSession(
                        signalURL: signalingURL,
                        requestedRoomID: roomName,
                        password: roomPassword,
                        requiresApproval: requireApproval
                    )
                    if started {
                        moderationService.reset()
                    }
                    isStarting = false
                }
            } label: {
                Label(
                    isStarting ? "Starting..." : "Start session",
                    systemImage: "video.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            if hostService.state == .ready || hostService.state == .connecting || hostService.state == .publishing {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Session code")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(hostService.sessionCode)
                            .font(.title3.bold())
                    }

                    Text("Room ID: \(hostService.activeRoomID.isEmpty ? "pending" : hostService.activeRoomID)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                ViewerListView(moderationService: moderationService)
                    .frame(maxHeight: 260)
            }

            Spacer()
        }
        .padding(24)
        .task {
            moderationService.bind(to: signalingService)
            signalingService.onViewerJoinRequest = { data in
                moderationService.handleJoinRequest(data)
            }
            signalingService.onViewerList = { data in
                moderationService.handleViewerList(data)
            }
            signalingService.onBroadcastEnded = {
                moderationService.reset()
            }
        }
    }
}
#endif
