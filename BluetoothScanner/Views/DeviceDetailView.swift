import Combine
import SwiftUI

struct DeviceDetailView: View {
    @EnvironmentObject private var appState: AppState
    @State private var currentDate = Date()
    @State private var lastSeenReferenceDate = Date()

    let deviceId: String
    var showsSheetTitle = false

    private var device: BluetoothDevice? {
        appState.device(id: deviceId)
    }

    private var classification: DetectedDeviceClassification? {
        device.map { appState.classification(for: $0) }
    }

    private var distanceSnapshot: BLEDistanceSnapshot {
        appState.distanceSnapshot(for: deviceId, at: currentDate)
    }

    private var latestObservation: ScanObservation? {
        appState.latestObservation(for: deviceId)
    }

    private var proximityState: ProximityState {
        appState.stabilizedProximity(for: deviceId, at: currentDate)
    }

    private let distanceTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let lastSeenTimer = Timer.publish(every: 8, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            if let device {
                VStack(alignment: .leading, spacing: 22) {
                    if showsSheetTitle {
                        SheetHeader(title: deviceTitle, subtitle: deviceCategorySubtitle)
                        .padding(.bottom, 10)
                    }

                    ProximitySummaryView(
                        distanceSnapshot: distanceSnapshot,
                        proximityState: proximityState
                    )

                    if !metadataRows(for: device).isEmpty {
                        DeviceMetadataSection(
                            rows: metadataRows(for: device)
                        )
                    }

                    AdvancedDeviceSection(
                        rows: advancedRows(for: device)
                    )
                }
                .padding(.horizontal, 20)
                .padding(.top, showsSheetTitle ? 28 : 18)
                .padding(.bottom, 32)
            } else {
                ContentUnavailableView(
                    "Device unavailable",
                    systemImage: "questionmark.circle",
                    description: Text("This device is no longer available.")
                )
                .padding(.top, 80)
            }
        }
        .background(Color(.systemGroupedBackground))
        .scrollContentBackground(.hidden)
        .navigationTitle(showsSheetTitle ? "" : deviceTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(distanceTimer) { date in
            currentDate = date
        }
        .onReceive(lastSeenTimer) { date in
            lastSeenReferenceDate = date
        }
        .onAppear {
            let now = Date()
            currentDate = now
            lastSeenReferenceDate = now
            appState.startTrackingDistance(for: deviceId)
        }
        .onDisappear {
            appState.stopTrackingDistance(for: deviceId)
        }
    }

    // MARK: - Computed Helpers

    private var deviceTitle: String {
        guard let device else { return "-" }
        if let name = cleanDisplayValue(device.displayName) {
            return name
        }
        if let classification {
            return classification.manufacturerName.map { "\($0) \(classification.categoryName)" } ?? classification.categoryName
        }
        return "-"
    }

    private var deviceCategorySubtitle: String? {
        guard let categoryName = cleanDisplayValue(classification?.categoryName),
              categoryName != "-"
        else {
            return nil
        }
        return categoryName
    }

    private func metadataRows(for device: BluetoothDevice) -> [DetailRow] {
        var rows: [DetailRow] = []

        if let classification {
            if let manufacturer = classification.manufacturer {
                rows.append(DetailRow(title: "Manufacturer", value: manufacturer))
            }
        }

        return rows
    }

    private func advancedRows(for device: BluetoothDevice) -> [DetailRow] {
        let rssi = latestObservation.map { appState.liveRSSI(for: device.id) ?? $0.rssi }

        let rows = [
            DetailRow(title: "Advertised name", value: displayValue(latestObservation?.advertisedName ?? device.advertisedName)),
            DetailRow(title: "Appearance", value: displayValue(classification?.appearance)),
            DetailRow(title: "Appearance value", value: latestObservation?.appearanceValue.map { String(format: "0x%04X", $0) } ?? "-"),
            DetailRow(title: "Category", value: displayValue(classification?.categoryName)),
            DetailRow(title: "Device identifier", value: displayValue(device.id)),
            DetailRow(title: "First seen", value: device.firstSeen.formatted(date: .abbreviated, time: .standard)),
            DetailRow(title: "Last seen", value: device.lastSeen.formattedRelative(to: lastSeenReferenceDate)),
            DetailRow(title: "Likely product", value: displayValue(classification?.likelyProduct)),
            DetailRow(title: "Manufacturer", value: displayValue(classification?.manufacturer)),
            DetailRow(title: "Manufacturer data", value: displayValue(latestObservation?.manufacturerDataSummary)),
            DetailRow(title: "Manufacturer ID", value: latestObservation?.manufacturerIdentifier.map { "0x\($0)" } ?? "-"),
            DetailRow(title: "Name", value: displayValue(device.displayName)),
            DetailRow(title: "RSSI", value: rssi.map { "\($0) dBm" } ?? "-"),
            DetailRow(title: "Service UUIDs", value: serviceUUIDsDisplayValue),
            DetailRow(title: "Status", value: displayValue(proximityState.rawValue)),
            DetailRow(title: "Tx power", value: latestObservation?.txPower.map { "\($0) dBm" } ?? "-"),
        ]

        return rows.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private var serviceUUIDsDisplayValue: String {
        guard let serviceUUIDs = latestObservation?.serviceUUIDs, !serviceUUIDs.isEmpty else {
            return "-"
        }
        return serviceUUIDs.joined(separator: ", ")
    }

    private func displayValue(_ value: String?) -> String {
        guard let value = cleanDisplayValue(value) else {
            return "-"
        }
        return value
    }

    private func cleanDisplayValue(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty,
              trimmedValue != "Unknown",
              trimmedValue != "Unknown BLE Device",
              trimmedValue != "Unknown Manufacturer"
        else {
            return nil
        }
        return trimmedValue
    }
}

private struct SheetHeader: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            if let subtitle {
                Text(subtitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

// MARK: - Proximity Summary View

private struct ProximitySummaryView: View {
    let distanceSnapshot: BLEDistanceSnapshot
    let proximityState: ProximityState

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            DetailMetricView(
                title: "Proximity",
                value: proximityState.rawValue,
                horizontalAlignment: .leading,
                frameAlignment: .leading
            )

            DetailMetricView(
                title: "Distance",
                value: distanceSnapshot.distanceText,
                horizontalAlignment: .trailing,
                frameAlignment: .trailing
            )
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(proximityState.color.opacity(0.18), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        "Proximity: \(proximityState.rawValue), Distance: \(distanceSnapshot.distanceText)"
    }
}

private struct DetailMetricView: View {
    let title: String
    let value: String
    let horizontalAlignment: HorizontalAlignment
    let frameAlignment: Alignment

    var body: some View {
        VStack(alignment: horizontalAlignment, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(value)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: frameAlignment)
    }
}

private struct DeviceMetadataSection: View {
    let rows: [DetailRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DetailRowsCard(rows: rows)
        }
    }
}

private struct AdvancedDeviceSection: View {
    let rows: [DetailRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Technical Details", systemImage: "slider.horizontal.3")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.tint)

            DetailRowsCard(rows: rows, backgroundStyle: .clear, horizontalPadding: 0)
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct DetailRowsCard: View {
    let rows: [DetailRow]
    var backgroundStyle = Color(.secondarySystemGroupedBackground)
    var horizontalPadding: CGFloat = 18

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                DetailRowView(row: row)

                if index < rows.count - 1 {
                    Divider()
                        .padding(.leading, 0)
                }
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, 8)
        .background(backgroundStyle, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct DetailRowView: View {
    let row: DetailRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(row.title)
                .font(.body)
                .foregroundStyle(.primary)

            Spacer(minLength: 20)

            Text(row.value)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .padding(.vertical, 14)
    }
}

private struct DetailRow: Hashable {
    let title: String
    let value: String
}

#Preview("Device Detail") {
    NavigationStack {
        DeviceDetailView(deviceId: PreviewData.phone.id)
    }
    .environmentObject(AppState.preview)
}

#Preview("Device Detail Sheet") {
    DeviceDetailView(deviceId: PreviewData.watch.id, showsSheetTitle: true)
        .environmentObject(AppState.preview)
}
