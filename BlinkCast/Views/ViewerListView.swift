import SwiftUI

struct ViewerListView: View {
    @ObservedObject var moderationService: ViewerModerationService
    @State private var selectedViewer: ViewerModerationService.Viewer?
    @State private var showingActionSheet = false

    var body: some View {
        NavigationStack {
            VStack {
                if moderationService.viewers.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "person.slash")
                            .font(.system(size: 48))
                            .foregroundStyle(.gray)
                        Text("No Viewers Connected")
                            .font(.headline)
                        Text("Waiting for viewers to join...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section("Pending Approval (\(moderationService.pendingCount))") {
                            ForEach(
                                moderationService.viewers.filter { $0.status == .pending },
                                id: \.clientId
                            ) { viewer in
                                ViewerRowView(viewer: viewer, onTap: {
                                    selectedViewer = viewer
                                    showingActionSheet = true
                                })
                            }
                        }

                        Section("Approved (\(moderationService.approvedCount))") {
                            ForEach(
                                moderationService.viewers.filter { $0.status == .approved },
                                id: \.clientId
                            ) { viewer in
                                ViewerRowView(viewer: viewer, onTap: {
                                    selectedViewer = viewer
                                    showingActionSheet = true
                                })
                            }
                        }
                    }
                    #if os(iOS)
                    .listStyle(.insetGrouped)
                    #else
                    .listStyle(.inset)
                    #endif
                }
            }
            .navigationTitle("Viewers")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .confirmationDialog(
                "Viewer Actions",
                isPresented: $showingActionSheet,
                presenting: selectedViewer
            ) { viewer in
                switch viewer.status {
                case .pending:
                    Button("Approve") {
                        moderationService.approve(viewer: viewer)
                    }
                    Button("Deny", role: .destructive) {
                        moderationService.deny(viewer: viewer)
                    }
                case .approved:
                    Button("Kick", role: .destructive) {
                        moderationService.kick(viewer: viewer)
                    }
                case .denied:
                    Button("Remove", role: .destructive) {
                        moderationService.kick(viewer: viewer)
                    }
                }
            } message: { viewer in
                Text("Manage viewer: \(viewer.clientId.prefix(12))...")
            }
        }
    }
}

struct ViewerRowView: View {
    let viewer: ViewerModerationService.Viewer
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(viewer.clientId.prefix(12).uppercased())
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)

                        Spacer()

                        statusBadge
                    }

                    Text(formatJoinedTime(viewer.joinedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var statusBadge: some View {
        Text(viewer.status.rawValue.capitalized)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor.opacity(0.2))
            .foregroundStyle(statusColor)
            .cornerRadius(4)
    }

    private var statusColor: Color {
        switch viewer.status {
        case .pending:
            return .orange
        case .approved:
            return .green
        case .denied:
            return .red
        }
    }

    private func formatJoinedTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    ViewerListView(moderationService: ViewerModerationService.shared)
}
