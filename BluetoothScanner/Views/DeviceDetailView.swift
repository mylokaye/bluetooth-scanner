import SwiftUI

struct DeviceDetailView: View {
    @EnvironmentObject private var appState: AppState

    let deviceId: String

    private var device: BluetoothDevice? {
        appState.device(id: deviceId)
    }

    private var observations: [ScanObservation] {
        appState.observations(for: deviceId)
    }

    var body: some View {
        List {
            if let device {
                Section("Device Metadata") {
                    LabeledContent("Name", value: device.displayName ?? "Unknown BLE Device")
                    LabeledContent("Advertised name", value: device.advertisedName ?? "None")
                    LabeledContent("Local device identifier", value: device.id)
                    LabeledContent("First seen", value: device.firstSeen.formatted(date: .abbreviated, time: .standard))
                    LabeledContent("Last seen", value: device.lastSeen.formatted(date: .abbreviated, time: .standard))
                    LabeledContent("Distance", value: appState.distanceCategory(for: device.id).rawValue)
                }

                Section("Trackability") {
                    Text("This device appears repeatedly and broadcasts a stable identifier.")
                    Text("It may be trackable over time by nearby Bluetooth scanners.")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)

                Section("Controls") {
                    Button(role: .destructive) {
                        appState.ignore(device: device)
                    } label: {
                        Label("Ignore device", systemImage: "eye.slash")
                    }
                }
            }

            Section("Recent Observations") {
                if observations.isEmpty {
                    Text("No stored observations for this device yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(observations.prefix(25)) { observation in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("\(observation.rssi) dBm")
                                    .font(.headline.monospacedDigit())
                                Spacer()
                                Text(observation.timestamp.formatted(date: .omitted, time: .standard))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if !observation.serviceUUIDs.isEmpty {
                                Text("Services: \(observation.serviceUUIDs.joined(separator: ", "))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if let manufacturerDataSummary = observation.manufacturerDataSummary {
                                Text("Manufacturer: \(manufacturerDataSummary)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if let txPower = observation.txPower {
                                Text("TX power: \(txPower)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle(device?.displayName ?? "Device Detail")
        .navigationBarTitleDisplayMode(.inline)
    }
}
