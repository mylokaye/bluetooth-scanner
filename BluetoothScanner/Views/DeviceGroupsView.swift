import SwiftUI

struct DeviceGroupsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        List {
            if appState.clusters.isEmpty {
                ContentUnavailableView(
                    "No groups",
                    systemImage: "rectangle.3.group",
                    description: Text("Start scanning to detect groups.")
                )
            } else {
                ForEach(appState.clusters) { cluster in
                    Section {
                        ClusterCard(cluster: cluster)
                    }
                }
            }
        }
        .navigationTitle("Device Groups")
    }
}

private struct ClusterCard: View {
    @EnvironmentObject private var appState: AppState

    let cluster: DeviceCluster

    private var title: String {
        switch cluster.clusterType {
        case .singleDevice:
            return "Single-device group"
        case .commonlySeenTogether:
            return "Commonly seen together"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        Text("\(cluster.confidenceLabel.rawValue.capitalized) · \(Int(cluster.confidenceScore * 100))%")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("Seen \(cluster.seenTogetherCount)x")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.thinMaterial, in: Capsule())
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(cluster.deviceIds, id: \.self) { deviceId in
                    if let device = appState.device(id: deviceId) {
                        NavigationLink {
                            DeviceDetailView(deviceId: deviceId)
                        } label: {
                            HStack {
                                Image(systemName: "dot.radiowaves.forward")
                                    .foregroundStyle(.tint)
                                Text(device.localAlias ?? device.displayName ?? "Unknown BLE Device")
                                Spacer()
                                Text(appState.distanceCategory(for: deviceId).rawValue)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Label(cluster.firstSeen.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar.badge.plus")
                Label(cluster.lastSeen.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }
}
