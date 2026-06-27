import SwiftUI

struct DeviceGroupsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        List {
            Section {
                ScreenHeader(
                    title: "Groups",
                    subtitle: "Devices whose signal strength moves together."
                )
            }
            .listRowInsets(EdgeInsets(top: 54, leading: 16, bottom: 0, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if appState.clusters.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No groups",
                        systemImage: "rectangle.3.group",
                        description: Text("Start scanning to detect correlated devices.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                }
                .listRowBackground(Color(.secondarySystemGroupedBackground))
            } else {
                Section("Detected") {
                    ForEach(Array(appState.clusters.enumerated()), id: \.element.id) { index, cluster in
                        ClusterRow(
                            index: index + 1,
                            cluster: cluster,
                            status: status(for: cluster)
                        )
                    }
                }
            }

            Section {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                    Text("Groups update as RSSI samples arrive.")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func status(for cluster: DeviceCluster) -> ClusterStatus {
        if let anchorDeviceId = cluster.anchorDeviceId {
            let activityStatus = appState.activityStatus(for: anchorDeviceId)
            let text: String
            switch activityStatus {
            case .online:
                text = "Online"
            case .recentlySeen, .offline:
                text = "Last seen \(cluster.lastSeen.formattedRelative())"
            }

            return ClusterStatus(text: text, color: activityStatus.color)
        }

        let elapsed = Date().timeIntervalSince(cluster.lastSeen)
        if elapsed <= 8 {
            return ClusterStatus(text: "Online", color: .green)
        } else if elapsed <= 30 {
            return ClusterStatus(text: "Last seen \(cluster.lastSeen.formattedRelative())", color: .orange)
        } else {
            return ClusterStatus(text: "Last seen \(cluster.lastSeen.formattedRelative())", color: .gray)
        }
    }
}

private struct ClusterStatus {
    let text: String
    let color: Color
}

private struct ClusterRow: View {
    let index: Int
    let cluster: DeviceCluster
    let status: ClusterStatus

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: cluster.isOwnerGroup ? "person.crop.circle.badge.questionmark" : "person.2")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 54, height: 54)
                .background(Color.blue.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 8) {
                Text(cluster.isOwnerGroup ? "Owner Group" : "Group \(index)")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                HStack(spacing: 8) {
                    Circle()
                        .fill(cluster.confidenceLabel.indicatorColor)
                        .frame(width: 8, height: 8)

                    Text("\(cluster.deviceIds.count) devices · \(Int((cluster.confidenceScore * 100).rounded()))%")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
            }

            Spacer(minLength: 10)

            Text(status.text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(status.color)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        "\(cluster.isOwnerGroup ? "Owner group" : "Group \(index)"), \(cluster.deviceIds.count) devices, \(Int((cluster.confidenceScore * 100).rounded())) percent confidence, \(status.text)"
    }
}

private extension ConfidenceLabel {
    var indicatorColor: Color {
        switch self {
        case .high:
            return .green
        case .medium:
            return .orange
        case .low:
            return .gray
        }
    }
}

#Preview("Device Groups") {
    NavigationStack {
        DeviceGroupsView()
    }
    .environmentObject(AppState.preview)
}
