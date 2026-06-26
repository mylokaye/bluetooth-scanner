import SwiftUI

struct LiveScanView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedCategory: KnownDeviceCategorySummary?
    @State private var selectedManufacturer: KnownDeviceManufacturerSummary?
    @State private var selectedOverview = LiveOverviewTab.categories

    var body: some View {
        List {
            Section {
                ScanActionContainer(
                    isScanning: appState.scanner.isScanning,
                    bluetoothState: appState.scanner.bluetoothState,
                    canClear: !appState.devices.isEmpty || !appState.observations.isEmpty,
                    onScanToggle: toggleScan,
                    onClear: appState.clearScanData
                )
            }

            Section {
                OverviewTabs(selection: $selectedOverview)

                switch selectedOverview {
                case .categories:
                    CategoryOverviewGrid(
                        summaries: appState.knownDeviceCategorySummaries,
                        selectedCategory: $selectedCategory
                    )
                case .manufacturers:
                    ManufacturerOverviewGrid(
                        summaries: appState.knownDeviceManufacturerSummaries,
                        selectedManufacturer: $selectedManufacturer
                    )
                }
            }

        }
        .navigationTitle("Live Scan")
        .navigationDestination(item: $selectedCategory) { summary in
            KnownCategoryDevicesView(summary: summary)
        }
        .navigationDestination(item: $selectedManufacturer) { summary in
            KnownManufacturerDevicesView(summary: summary)
        }
    }

    private func toggleScan() {
        if appState.scanner.isScanning {
            appState.stopScan()
        } else {
            appState.startScan()
        }
    }
}

private enum LiveOverviewTab: String, CaseIterable, Identifiable {
    case categories = "Categories"
    case manufacturers = "Manufacturers"

    var id: String { rawValue }
}

private struct ScanActionContainer: View {
    let isScanning: Bool
    let bluetoothState: String
    let canClear: Bool
    let onScanToggle: () -> Void
    let onClear: () -> Void

    private var statusText: String {
        switch bluetoothState {
        case "Powered on":
            return "Powered On"
        case "Powered off":
            return "Bluetooth Off"
        default:
            return bluetoothState
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Button(action: onScanToggle) {
                    Label(isScanning ? "Stop" : "Scan", systemImage: isScanning ? "stop.fill" : "dot.radiowaves.left.and.right")
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.borderedProminent)
                .tint(isScanning ? .red : .blue)

                Button(role: .destructive, action: onClear) {
                    Label("Clear", systemImage: "trash")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: 96, height: 52)
                }
                .buttonStyle(.bordered)
                .disabled(!canClear)
                .accessibilityLabel("Clear")
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(isScanning ? Color.green : Color.secondary.opacity(0.55))
                    .frame(width: 8, height: 8)

                Text(statusText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Text(isScanning ? "Scanning" : "Idle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            .padding(.horizontal, 2)
        }
        .padding(.vertical, 8)
    }
}

private struct OverviewTabs: View {
    @Binding var selection: LiveOverviewTab

    var body: some View {
        Picker("Live overview", selection: $selection) {
            ForEach(LiveOverviewTab.allCases) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.vertical, 4)
    }
}

private struct CategoryOverviewGrid: View {
    let summaries: [KnownDeviceCategorySummary]
    @Binding var selectedCategory: KnownDeviceCategorySummary?

    var body: some View {
        if summaries.isEmpty {
            ContentUnavailableView(
                "No devices yet",
                systemImage: "antenna.radiowaves.left.and.right",
                description: Text("Start scanning to populate categories.")
            )
        } else {
            SummaryGrid {
                ForEach(summaries) { summary in
                    Button {
                        selectedCategory = summary
                    } label: {
                        SummaryTile(
                            symbolName: summary.symbolName,
                            title: summary.categoryName,
                            count: summary.count
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct ManufacturerOverviewGrid: View {
    let summaries: [KnownDeviceManufacturerSummary]
    @Binding var selectedManufacturer: KnownDeviceManufacturerSummary?

    var body: some View {
        if summaries.isEmpty {
            ContentUnavailableView(
                "No manufacturers yet",
                systemImage: "building.2",
                description: Text("Start scanning to populate manufacturers.")
            )
        } else {
            SummaryGrid {
                ForEach(summaries) { summary in
                    Button {
                        selectedManufacturer = summary
                    } label: {
                        SummaryTile(
                            symbolName: "building.2",
                            title: summary.manufacturerName,
                            count: summary.count
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct SummaryGrid<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ],
            spacing: 12
        ) {
            content
        }
        .padding(.vertical, 4)
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
        .sheet(item: $selectedDevice) { device in
            DeviceDetailPopover(deviceId: device.id)
                .presentationDetents([.fraction(0.58), .large])
                .presentationDragIndicator(.hidden)
        }
    }
}

private struct KnownManufacturerDevicesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedDevice: BluetoothDevice?

    let summary: KnownDeviceManufacturerSummary

    private var devices: [BluetoothDevice] {
        appState.devices(forKnownManufacturer: summary.manufacturerName)
    }

    var body: some View {
        List {
            if devices.isEmpty {
                ContentUnavailableView(
                    "No devices",
                    systemImage: "building.2",
                    description: Text("No devices from this manufacturer.")
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
        .navigationTitle(summary.manufacturerName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedDevice) { device in
            DeviceDetailPopover(deviceId: device.id)
                .presentationDetents([.fraction(0.58), .large])
                .presentationDragIndicator(.hidden)
        }
    }
}

private struct DeviceDetailPopover: View {
    let deviceId: String

    var body: some View {
        DeviceDetailView(deviceId: deviceId, showsSheetTitle: true)
    }
}

private struct SummaryTile: View {
    let symbolName: String
    let title: String
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Image(systemName: symbolName)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 32, height: 32)
                    .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Spacer()

                Text("\(count)")
                    .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Text(title)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(count) devices")
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
        if let displayName = device.displayName, displayName != "Unknown BLE Device", displayName != "-" {
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
