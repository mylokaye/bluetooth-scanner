import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    private var ignoredDevices: [BluetoothDevice] {
        appState.devices.filter(\.isIgnored)
    }

    var body: some View {
        List {
            Section("Scanning") {
                LabeledContent("Mode", value: "While app is open")
                LabeledContent("Connections", value: "Never connects or pairs")
                LabeledContent("Storage", value: "Local JSON")
            }

            Section("Ignored Devices") {
                if ignoredDevices.isEmpty {
                    Text("None")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(ignoredDevices) { device in
                        VStack(alignment: .leading) {
                            Text(device.displayName ?? "Unknown BLE Device")
                            Text(device.id)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if let lastStorageError = appState.lastStorageError {
                Section("Storage Error") {
                    Text(lastStorageError)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Settings")
    }
}
