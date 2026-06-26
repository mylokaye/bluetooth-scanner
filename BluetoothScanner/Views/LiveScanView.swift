import SwiftUI

struct LiveScanView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Button {
                            appState.startScan()
                        } label: {
                            Label("Start Scan", systemImage: "play.fill")
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(appState.scanner.isScanning)

                        Button(role: .destructive) {
                            appState.stopScan()
                        } label: {
                            Label("Stop", systemImage: "stop.fill")
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!appState.scanner.isScanning)

                        Button(role: .destructive) {
                            appState.clearScanData()
                        } label: {
                            Label("Clear", systemImage: "trash")
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(appState.devices.isEmpty && appState.observations.isEmpty)
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(appState.scanner.isScanning ? "Scanning" : "Scan paused")
                                .font(.headline)
                            Text("Bluetooth: \(appState.scanner.bluetoothState)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if appState.scanner.bluetoothState != "Powered on" {
                        Text(appState.scanner.bluetoothState)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }

            Section("Categories") {
                if appState.knownDeviceCategorySummaries.isEmpty {
                    ContentUnavailableView(
                        "No devices yet",
                        systemImage: "antenna.radiowaves.left.and.right",
                        description: Text("Start scanning to populate categories.")
                    )
                } else {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)
                        ],
                        spacing: 12
                    ) {
                        ForEach(appState.knownDeviceCategorySummaries) { summary in
                            NavigationLink {
                                KnownCategoryDevicesView(summary: summary)
                            } label: {
                                CategorySummaryTile(summary: summary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

        }
        .navigationTitle("Live Scan")
    }
}

private struct KnownCategoryDevicesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedDevice: BluetoothDevice?

    let summary: KnownDeviceCategorySummary

    private var devices: [BluetoothDevice] {
        appState.devices(inKnownCategory: summary.categoryName)
    }

    var body: some View {
        List {
            if devices.isEmpty {
                ContentUnavailableView(
                    "No devices",
                    systemImage: summary.symbolName,
                    description: Text("No devices in this category.")
                )
            } else {
                Section {
                    ForEach(devices) { device in
                        Button {
                            selectedDevice = device
                        } label: {
                            DeviceRow(device: device)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                appState.ignore(device: device)
                            } label: {
                                Label("Ignore", systemImage: "eye.slash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(summary.categoryName)
        .navigationBarTitleDisplayMode(.inline)
        .popover(item: $selectedDevice) { device in
            DeviceDetailPopover(deviceId: device.id)
                .frame(minWidth: 360, minHeight: 520)
                .presentationCompactAdaptation(.sheet)
        }
    }
}

private struct DeviceDetailPopover: View {
    @Environment(\.dismiss) private var dismiss

    let deviceId: String

    var body: some View {
        NavigationStack {
            DeviceDetailView(deviceId: deviceId)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
        }
    }
}

private struct CategorySummaryTile: View {
    let summary: KnownDeviceCategorySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: summary.symbolName)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 28, height: 28)

                Spacer()

                Text("\(summary.count)")
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.primary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(summary.categoryName)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let lastSeen = summary.lastSeen {
                    Text("Last seen \(lastSeen.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(summary.categoryName), \(summary.count) devices")
    }
}

private struct DeviceRow: View {
    @EnvironmentObject private var appState: AppState

    let device: BluetoothDevice

    private var classification: DeviceClassification {
        appState.classification(for: device)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: classification.symbolName)
                .foregroundStyle(.tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 5) {
                Text(displayName)
                    .font(.headline)
                Text(device.advertisedName ?? "No advertised name")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Last seen \(device.lastSeen.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if let rssi = appState.liveRSSI(for: device.id) {
                    Text("\(rssi) dBm")
                        .font(.callout.monospacedDigit())
                }
                Text(appState.distanceCategory(for: device.id).rawValue)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var detailText: String {
        if let manufacturerName = classification.manufacturerName {
            return "\(classification.categoryName) · \(manufacturerName)"
        }

        return classification.categoryName
    }

    private var displayName: String {
        if let localAlias = device.localAlias {
            return localAlias
        }
        if let displayName = device.displayName, displayName != "Unknown BLE Device" {
            return displayName
        }
        if let manufacturerName = classification.manufacturerName {
            return "\(manufacturerName) \(classification.categoryName)"
        }
        return classification.categoryName
    }
}
