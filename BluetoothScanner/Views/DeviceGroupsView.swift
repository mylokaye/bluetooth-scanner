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

    /// Devices in the cluster split into named and unnamed groups.
    private var deviceGroups: (known: [(id: String, name: String)], unknownCount: Int) {
        var known: [(id: String, name: String)] = []
        var unknownCount = 0

        for deviceId in cluster.deviceIds {
            guard let device = appState.device(id: deviceId) else { continue }
            let name = device.localAlias ?? device.displayName

            if let name, name != "Unknown BLE Device", name != "-" {
                known.append((id: deviceId, name: name))
            } else {
                unknownCount += 1
            }
        }

        return (known, unknownCount)
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
                // Named devices shown individually with navigation.
                ForEach(deviceGroups.known, id: \.id) { item in
                    NavigationLink {
                        DeviceDetailView(deviceId: item.id)
                    } label: {
                        HStack {
                            Image(systemName: "dot.radiowaves.forward")
                                .foregroundStyle(.tint)
                            Text(item.name)
                        }
                    }
                }

                // Collapse all unnamed devices into a single summary row.
                if deviceGroups.unknownCount > 0 {
                    HStack {
                        Image(systemName: "dot.radiowaves.forward")
                            .foregroundStyle(.secondary)
                        Text("- Devices (\(deviceGroups.unknownCount))")
                            .foregroundStyle(.secondary)
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
