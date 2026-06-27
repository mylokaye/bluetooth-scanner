import SwiftUI

struct DeviceGroupsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ScreenHeader(
                    title: "Groups",
                    subtitle: "Devices that are often seen together."
                )
                .padding(.top, 54)

                if appState.clusters.isEmpty {
                    ContentUnavailableView(
                        "No groups",
                        systemImage: "rectangle.3.group",
                        description: Text("Start scanning to detect groups.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 48)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                } else {
                    VStack(spacing: 12) {
                        ForEach(Array(appState.clusters.enumerated()), id: \.element.id) { index, cluster in
                            ClusterCard(index: index + 1, cluster: cluster)
                        }
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                        Text("Groups are created automatically.")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 120)
        }
        .background(Color(.systemGroupedBackground))
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct ClusterCard: View {
    let index: Int
    let cluster: DeviceCluster

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "person.2")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 58, height: 58)
                .background(Color.blue.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 8) {
                Text("Group \(index)")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Circle()
                        .fill(cluster.confidenceLabel.indicatorColor)
                        .frame(width: 8, height: 8)

                    Text("\(cluster.confidenceLabel.displayName) · \(Int(cluster.confidenceScore * 100))%")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
            }

            Spacer(minLength: 10)

            Text("Seen \(cluster.seenTogetherCount)x")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary.opacity(0.84))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 14, x: 0, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Group \(index), \(cluster.confidenceLabel.displayName), \(Int(cluster.confidenceScore * 100)) percent confidence, seen \(cluster.seenTogetherCount) times")
    }
}

private extension ConfidenceLabel {
    var displayName: String {
        rawValue.capitalized
    }

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
