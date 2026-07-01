import SwiftUI

struct KnownCategoryDevicesView: View {
    @Environment(AppState.self) private var appState
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
                    }
                }
            }
        }
        .navigationTitle(summary.categoryName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedDevice) { device in
            DeviceDetailPopover(deviceId: device.id)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

struct KnownManufacturerDevicesView: View {
    @Environment(AppState.self) private var appState
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
                    }
                }
            }
        }
        .navigationTitle(summary.manufacturerName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedDevice) { device in
            DeviceDetailPopover(deviceId: device.id)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

struct DeviceDetailPopover: View {
    let deviceId: String

    var body: some View {
        DeviceDetailView(deviceId: deviceId, showsSheetTitle: true)
    }
}

struct DeviceRow: View {
    @Environment(AppState.self) private var appState

    let device: BluetoothDevice

    private var classification: DetectedDeviceClassification {
        appState.classification(for: device)
    }

    private var proximityState: ProximityState {
        appState.stabilizedProximity(for: device.id)
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

            ProximityPill(state: proximityState)
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

private struct ProximityPill: View {
    let state: ProximityState

    var body: some View {
        Text(state.rawValue)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(state.color, in: Capsule())
    }
}
