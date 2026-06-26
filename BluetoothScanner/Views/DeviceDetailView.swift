import SwiftUI

struct DeviceDetailView: View {
    @EnvironmentObject private var appState: AppState
    @State private var currentDate = Date()
    @State private var isAdvancedExpanded = false

    let deviceId: String

    private var device: BluetoothDevice? {
        appState.device(id: deviceId)
    }

    private var classification: DetectedDeviceClassification? {
        device.map { appState.classification(for: $0) }
    }

    private var distanceSnapshot: BLEDistanceSnapshot {
        appState.distanceSnapshot(for: deviceId, at: currentDate)
    }

    private var activityStatus: ActivityStatus {
        appState.activityStatus(for: deviceId, at: currentDate)
    }

    private var latestObservation: ScanObservation? {
        appState.observations(for: deviceId).first
    }

    private let distanceTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        List {
            if let device {
                Section {
                    ActivityStatusView(
                        status: activityStatus,
                        subtitle: activitySubtitle,
                        distanceSnapshot: distanceSnapshot
                    )
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))

                Section("Device Metadata") {
                    LabeledContent("Name", value: device.displayName ?? "Unknown BLE Device")
                    LabeledContent("Advertised name", value: device.advertisedName ?? "None")
                    if let classification {
                        LabeledContent("Manufacturer", value: manufacturerDisplayName(for: classification))
                        LabeledContent("Category", value: classification.categoryName)
                    }
                }

                Section {
                    DisclosureGroup(isExpanded: $isAdvancedExpanded) {
                        LabeledContent("Distance", value: distanceSnapshot.distanceText)
                        LabeledContent("Status", value: distanceSnapshot.proximity.rawValue)
                        LabeledContent("Distance confidence", value: "\(distanceSnapshot.confidence)%")
                        LabeledContent("Device identifier", value: device.id)
                        LabeledContent("First seen", value: device.firstSeen.formatted(date: .abbreviated, time: .standard))
                        LabeledContent("Last seen", value: device.lastSeen.formatted(date: .abbreviated, time: .standard))
                        LabeledContent("Distance band", value: appState.distanceCategory(for: device.id).rawValue)

                        if let classification {
                            if let likelyProduct = classification.likelyProduct {
                                LabeledContent("Likely product", value: likelyProduct)
                            }

                            LabeledContent("Classification confidence", value: "\(classification.confidence)%")

                            if let appearance = classification.appearance {
                                LabeledContent("Appearance", value: appearance)
                            }
                        }

                        if let latestObservation {
                            let rssi = appState.liveRSSI(for: device.id) ?? latestObservation.rssi
                            LabeledContent("RSSI", value: "\(rssi) dBm")

                            if let txPower = latestObservation.txPower {
                                LabeledContent("Tx power", value: "\(txPower) dBm")
                            }

                            if let manufacturerIdentifier = latestObservation.manufacturerIdentifier {
                                LabeledContent("Manufacturer ID", value: "0x\(manufacturerIdentifier)")
                            }

                            if let appearanceValue = latestObservation.appearanceValue {
                                LabeledContent("Appearance value", value: String(format: "0x%04X", appearanceValue))
                            }

                            if !latestObservation.serviceUUIDs.isEmpty {
                                LabeledContent("Service UUIDs", value: latestObservation.serviceUUIDs.joined(separator: ", "))
                            }

                            if let manufacturerDataSummary = latestObservation.manufacturerDataSummary {
                                LabeledContent("Manufacturer data", value: manufacturerDataSummary)
                            }
                        }

                        if let classification, !classification.evidence.isEmpty {
                            ForEach(classification.evidence, id: \.self) { item in
                                LabeledContent(
                                    item.source,
                                    value: "\(item.value) (+\(item.confidenceContribution))"
                                )
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
        .onAppear {
            appState.startTrackingDistance(for: deviceId)
        }
        .onDisappear {
            appState.stopTrackingDistance(for: deviceId)
        }
    }

    // MARK: - Computed Helpers

    private var activitySubtitle: String {
        guard let device else { return "Never seen" }

        switch activityStatus {
        case .online:
            return "Currently nearby"
        case .recentlySeen:
            return "Last seen \(device.lastSeen.formattedRelative(to: currentDate))"
        case .offline:
            return "Last seen \(device.lastSeen.formattedRelative(to: currentDate))"
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

    private func manufacturerDisplayName(for classification: DetectedDeviceClassification) -> String {
        classification.manufacturer ?? "Unknown"
    }
}

// MARK: - Activity Status View

private struct ActivityStatusView: View {
    let status: ActivityStatus
    let subtitle: String
    let distanceSnapshot: BLEDistanceSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(status.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(status.color, in: Capsule())

                Spacer()

                if distanceSnapshot.isAvailable {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(distanceSnapshot.distanceText)
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .monospacedDigit()
                        Text("\(distanceSnapshot.confidence)% confidence")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = ["Activity status: \(status.displayName)", subtitle]
        if distanceSnapshot.isAvailable {
            parts.append("Distance: \(distanceSnapshot.distanceText)")
            parts.append("Confidence: \(distanceSnapshot.confidence)%")
        }
        return parts.joined(separator: ", ")
    }
}
