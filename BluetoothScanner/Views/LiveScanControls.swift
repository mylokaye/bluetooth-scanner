import SwiftUI

enum LiveOverviewTab: String, CaseIterable, Identifiable {
    case categories = "Categories"
    case manufacturers = "Manufacturers"

    var id: String { rawValue }
}

struct ScanActionHeader: View {
    let scanner: BluetoothScannerService
    let canClear: Bool
    let deviceCount: Int
    let nearbyDeviceCount: Int
    let groupCount: Int
    let onScanToggle: () -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                Button(action: onScanToggle) {
                    HStack(spacing: 16) {
                        Image(systemName: scanner.isScanning ? "stop.fill" : "dot.radiowaves.left.and.right")
                            .font(.title2.weight(.semibold))
                            .frame(width: 44)

                        Text(scanner.isScanning ? "Stop Scan" : "Start Scan")
                            .font(.title2.bold())
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(scanner.isScanning ? Color.red : Color.blue, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(scanner.isScanning ? "Stop scan" : "Start scan")

                Button(role: .destructive, action: onClear) {
                    Image(systemName: "trash")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.blue)
                        .frame(width: 68, height: 64)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color(.separator).opacity(0.35), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canClear)
                .opacity(canClear ? 1 : 0.45)
                .accessibilityLabel("Clear scan data")
            }

            HStack(spacing: 10) {
                ScanMetricChip(title: "Devices", value: deviceCount, systemImage: "sensor.tag.radiowaves.forward")
                ScanMetricChip(title: "Nearby", value: nearbyDeviceCount, systemImage: "location")
                ScanMetricChip(title: "Groups", value: groupCount, systemImage: "square.grid.2x2")
            }

            HStack(spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.blue)

                Text("Scans only while this app is open. Never connects or pairs.")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(.separator).opacity(0.28), lineWidth: 1)
            )
        }
        .padding(.vertical, 10)
    }
}

private struct ScanMetricChip: View {
    let title: String
    let value: Int
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.blue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 0) {
                Text(value, format: .number)
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(.separator).opacity(0.28), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value)")
    }
}

struct OverviewTabs: View {
    @Binding var selection: LiveOverviewTab

    var body: some View {
        Picker("Live overview", selection: $selection) {
            ForEach(LiveOverviewTab.allCases) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.top, 4)
        .padding(.bottom, 0)
    }
}
