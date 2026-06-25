import SwiftUI

struct LiveScanView: View {
    @EnvironmentObject private var appState: AppState

    private var visibleDevices: [BluetoothDevice] {
        appState.devices
            .filter { !$0.isIgnored }
            .sorted { $0.lastSeen > $1.lastSeen }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(appState.scanner.isScanning ? "Scanning" : "Scan paused")
                                .font(.headline)
                            Text("Bluetooth: \(appState.scanner.bluetoothState)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        scanButton
                    }

                    Text(appState.scanner.authorizationMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            Section("Live Devices") {
                if visibleDevices.isEmpty {
                    ContentUnavailableView(
                        "No devices yet",
                        systemImage: "antenna.radiowaves.left.and.right",
                        description: Text("Start scan to observe nearby BLE advertisements while the app is open.")
                    )
                } else {
                    ForEach(visibleDevices) { device in
                        NavigationLink {
                            DeviceDetailView(deviceId: device.id)
                        } label: {
                            DeviceRow(device: device)
                        }
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

            Section("Audit Note") {
                Text("It may be trackable over time by nearby Bluetooth scanners.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Live Scan")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    appState.scanner.isScanning ? appState.stopScan() : appState.startScan()
                } label: {
                    Image(systemName: appState.scanner.isScanning ? "stop.fill" : "play.fill")
                }
                .accessibilityLabel(appState.scanner.isScanning ? "Stop scan" : "Start scan")
            }
        }
    }

    @ViewBuilder
    private var scanButton: some View {
        if appState.scanner.isScanning {
            Button(role: .destructive) {
                appState.stopScan()
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button {
                appState.startScan()
            } label: {
                Label("Start", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

private struct DeviceRow: View {
    @EnvironmentObject private var appState: AppState

    let device: BluetoothDevice

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sensor.tag.radiowaves.forward")
                .foregroundStyle(.tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 5) {
                Text(device.localAlias ?? device.displayName ?? "Unknown BLE Device")
                    .font(.headline)
                Text(device.advertisedName ?? "No advertised name")
                    .font(.subheadline)
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
}
