import SwiftUI

struct LiveScanView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedCategory: KnownDeviceCategorySummary?

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
                            Button {
                                selectedCategory = summary
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
        .navigationDestination(item: $selectedCategory) { summary in
            KnownCategoryDevicesView(summary: summary)
        }
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

    private var classification: DetectedDeviceClassification {
        appState.classification(for: device)
    }

    private var activityStatus: ActivityStatus {
        appState.activityStatus(for: device.id)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: classification.symbolName)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(displayName)
                    .font(.headline)
                if let advertisedName = device.advertisedName {
                    Text(advertisedName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            ActivityPill(status: activityStatus)
        }
        .padding(.vertical, 6)
    }

    private var detailText: String {
        if let manufacturerName = classification.manufacturer {
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
        if let manufacturerName = classification.manufacturer {
            return "\(manufacturerName) \(classification.categoryName)"
        }
        return classification.categoryName
    }
}

private struct ActivityPill: View {
    let status: ActivityStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(status.color, in: Capsule())
    }
}
