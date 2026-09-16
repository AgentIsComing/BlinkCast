import SwiftUI

struct RoomAnalyticsView: View {
    @ObservedObject var analyticsService: RoomAnalyticsService
    @State private var autoRefreshEnabled = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let stats = analyticsService.stats {
                    ScrollView {
                        VStack(spacing: 16) {
                            // Viewer Stats
                            GroupBox(label: Label("Viewers", systemImage: "person.3")) {
                                VStack(alignment: .leading, spacing: 12) {
                                    StatRow("Total Connected", value: "\(stats.totalViewers)")
                                    StatRow("Approved", value: "\(stats.approvedViewers)", color: .green)
                                    StatRow("Pending", value: "\(stats.pendingViewers)", color: .orange)
                                    Divider()
                                    StatRow("Peak Count", value: "\(stats.peakViewerCount)")
                                }
                            }

                            // Network Stats
                            GroupBox(label: Label("Network Performance", systemImage: "wifi")) {
                                VStack(alignment: .leading, spacing: 12) {
                                    StatRow("Total Bitrate", value: formatBitrate(stats.totalBitrate))
                                    StatRow("Avg Latency", value: "\(stats.averageLatency)ms", color: latencyColor(stats.averageLatency))
                                    StatRow("Packet Loss", value: String(format: "%.2f%%", stats.averagePacketLoss * 100), color: packetLossColor(stats.averagePacketLoss))
                                }
                            }

                            // Session Stats
                            GroupBox(label: Label("Session", systemImage: "clock")) {
                                VStack(alignment: .leading, spacing: 12) {
                                    StatRow("Duration", value: formatDuration(stats.sessionDuration))
                                    StatRow("Host Active", value: stats.isHostActive ? "Yes" : "No", color: stats.isHostActive ? .green : .red)
                                    if let lastUpdate = analyticsService.lastUpdate {
                                        StatRow("Last Update", value: formatRelativeTime(lastUpdate), color: .secondary)
                                    }
                                }
                            }

                            Spacer(minLength: 20)
                        }
                        .padding()
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 48))
                            .foregroundStyle(.gray)
                        Text("No Analytics Data")
                            .font(.headline)
                        Text("Waiting for viewer connections...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Room Analytics")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    HStack(spacing: 12) {
                        if analyticsService.isRefreshing {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Button(action: {
                                Task {
                                    await analyticsService.requestAnalytics()
                                }
                            }) {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                    }
                }
            }
            .onAppear {
                if autoRefreshEnabled {
                    analyticsService.startPeriodicAnalytics(interval: 5.0)
                }
            }
            .onDisappear {
                analyticsService.stopPeriodicAnalytics()
            }
        }
    }

    private func formatBitrate(_ bitrate: Int64) -> String {
        if bitrate >= 1_000_000_000 {
            return String(format: "%.1f Gbps", Double(bitrate) / 1_000_000_000)
        } else if bitrate >= 1_000_000 {
            return String(format: "%.1f Mbps", Double(bitrate) / 1_000_000)
        } else if bitrate >= 1_000 {
            return String(format: "%.1f Kbps", Double(bitrate) / 1_000)
        } else {
            return "\(bitrate) bps"
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: seconds) ?? "0s"
    }

    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func latencyColor(_ rtt: Int) -> Color {
        switch rtt {
        case 0..<50:
            return .green
        case 50..<100:
            return .yellow
        default:
            return .red
        }
    }

    private func packetLossColor(_ loss: Double) -> Color {
        switch loss {
        case 0..<0.01:
            return .green
        case 0.01..<0.05:
            return .yellow
        default:
            return .red
        }
    }
}

struct StatRow: View {
    let label: String
    let value: String
    var color: Color = .primary

    init(_ label: String, value: String, color: Color = .primary) {
        self.label = label
        self.value = value
        self.color = color
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.callout)
                .fontWeight(.semibold)
                .foregroundStyle(color)
        }
    }
}

#Preview {
    RoomAnalyticsView(analyticsService: RoomAnalyticsService.shared)
}
