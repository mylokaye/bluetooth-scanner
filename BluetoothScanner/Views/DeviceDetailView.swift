import SwiftUI

struct DeviceDetailView: View {
    @EnvironmentObject private var appState: AppState
    @State private var currentDate = Date()
    @State private var isAdvancedExpanded = false

    let deviceId: String

    private var device: BluetoothDevice? {
        appState.device(id: deviceId)
    }

    private var classification: DeviceClassification? {
        device.map { appState.classification(for: $0) }
    }

    private var distanceSnapshot: BLEDistanceSnapshot {
        appState.distanceSnapshot(for: deviceId, at: currentDate)
    }

    private let distanceTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        List {
            if let device {
                Section {
                    DistanceSummaryView(snapshot: distanceSnapshot)
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))

                Section("Device Metadata") {
                    LabeledContent("Name", value: device.displayName ?? "Unknown BLE Device")
                    LabeledContent("Advertised name", value: device.advertisedName ?? "None")
                    if let classification {
                        LabeledContent("Category", value: classification.categoryName)
                        LabeledContent("Manufacturer", value: manufacturerDisplayName(for: classification))
                        if let appearanceName = classification.appearanceName {
                            LabeledContent("Appearance", value: appearanceName)
                        }
                    }
                }

                Section {
                    DisclosureGroup(isExpanded: $isAdvancedExpanded) {
                        LabeledContent("Device identifier", value: device.id)
                        LabeledContent("First seen", value: device.firstSeen.formatted(date: .abbreviated, time: .standard))
                        LabeledContent("Last seen", value: device.lastSeen.formatted(date: .abbreviated, time: .standard))
                        LabeledContent("Distance band", value: appState.distanceCategory(for: device.id).rawValue)

                        if let classification {
                            if let manufacturerIdentifier = classification.manufacturerIdentifier {
                                LabeledContent("Manufacturer ID", value: "0x\(manufacturerIdentifier)")
                            }

                            if let appearanceValue = classification.appearanceValue {
                                LabeledContent("Appearance value", value: String(format: "0x%04X", appearanceValue))
                            }

                            if let matchedUUID = classification.matchedUUID {
                                LabeledContent("Matched service", value: "0x\(matchedUUID)")
                            }
                        }
                    } label: {
                        Label("Advanced", systemImage: "slider.horizontal.3")
                    }
                }

                Section("Controls") {
                    Button(role: .destructive) {
                        appState.ignore(device: device)
                    } label: {
                        Label("Ignore device", systemImage: "eye.slash")
                    }
                }
            }
        }
        .navigationTitle(deviceTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(distanceTimer) { date in
            currentDate = date
        }
    }

    private var deviceTitle: String {
        guard let device else { return "Device Detail" }
        if let name = device.displayName, name != "Unknown BLE Device" {
            return name
        }
        if let classification {
            return classification.manufacturerName.map { "\($0) \(classification.categoryName)" } ?? classification.categoryName
        }
        return "Device Detail"
    }

    private func manufacturerDisplayName(for classification: DeviceClassification) -> String {
        classification.manufacturerName ?? "Unknown"
    }
}

private struct DistanceSummaryView: View {
    let snapshot: BLEDistanceSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Distance")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(snapshot.distanceText)
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Spacer()

                Image(systemName: snapshot.isAvailable ? "dot.radiowaves.left.and.right" : "slash.circle")
                    .font(.title2)
                    .foregroundStyle(snapshot.isAvailable ? Color.accentColor : Color.secondary)
                    .frame(width: 44, height: 44)
                    .background(.thinMaterial, in: Circle())
            }

            HStack(spacing: 12) {
                MetricPill(title: "Status", value: snapshot.proximity.rawValue)
                MetricPill(title: "Confidence", value: "\(snapshot.confidence)%")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Distance \(snapshot.distanceText), status \(snapshot.proximity.rawValue), confidence \(snapshot.confidence) percent")
    }
}

private struct MetricPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
