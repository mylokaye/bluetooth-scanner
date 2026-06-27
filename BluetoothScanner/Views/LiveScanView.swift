import SwiftUI
import UIKit

struct ScreenHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if let subtitle {
                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LiveScanView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedCategory: KnownDeviceCategorySummary?
    @State private var selectedManufacturer: KnownDeviceManufacturerSummary?
    @State private var selectedOverview = LiveOverviewTab.categories

    private var visibleDeviceCount: Int {
        appState.devices.count
    }

    private var nearbyDeviceCount: Int {
        appState.devices.filter { device in
            let proximity = appState.stabilizedProximity(for: device.id)
            return proximity == .close || proximity == .nearby
        }.count
    }

    var body: some View {
        List {
            Section {
                ScreenHeader(title: "Live Scan")
            }
            .listRowInsets(EdgeInsets(top: 54, leading: 16, bottom: 0, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            Section {
                ScanActionHeader(
                    isScanning: appState.scanner.isScanning,
                    canClear: !appState.devices.isEmpty || !appState.observations.isEmpty,
                    deviceCount: visibleDeviceCount,
                    nearbyDeviceCount: nearbyDeviceCount,
                    groupCount: appState.clusters.count,
                    onScanToggle: toggleScan,
                    onClear: appState.clearScanData
                )
            }

            Section("Overview") {
                OverviewTabs(selection: $selectedOverview)
                    .listRowSeparator(.hidden)

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
            .listRowSeparator(.hidden)

        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $selectedCategory) { summary in
            KnownCategoryDevicesView(summary: summary)
                .toolbar(.visible, for: .navigationBar)
        }
        .navigationDestination(item: $selectedManufacturer) { summary in
            KnownManufacturerDevicesView(summary: summary)
                .toolbar(.visible, for: .navigationBar)
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

private struct ScanActionHeader: View {
    let isScanning: Bool
    let canClear: Bool
    let deviceCount: Int
    let nearbyDeviceCount: Int
    let groupCount: Int
    let onScanToggle: () -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                Button(action: onScanToggle) {
                    HStack(spacing: 16) {
                        Image(systemName: isScanning ? "stop.fill" : "dot.radiowaves.left.and.right")
                            .font(.system(size: 24, weight: .semibold))
                            .frame(width: 44)

                        Text(isScanning ? "Stop Scan" : "Start Scan")
                            .font(.title2.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(isScanning ? Color.red : Color.blue, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isScanning ? "Stop scan" : "Start scan")

                Button(role: .destructive, action: onClear) {
                    Image(systemName: "trash")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.blue)
                        .frame(width: 68, height: 64)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color(.separator).opacity(0.35), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canClear)
                .opacity(canClear ? 1 : 0.45)
                .accessibilityLabel("Clear scan data")
            }

            HStack(spacing: 10) {
                ScanMetricChip(title: "Devices", value: deviceCount, systemImage: "sensor.tag.radiowaves.forward")
                ScanMetricChip(title: "Nearby", value: nearbyDeviceCount, systemImage: "location")
                ScanMetricChip(title: "Groups", value: groupCount, systemImage: "square.grid.2x2")
            }

            HStack(spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.blue)

                Text("Scans only while this app is open. Never connects or pairs.")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(.separator).opacity(0.28), lineWidth: 1)
            )
        }
        .padding(.vertical, 10)
    }
}

private struct ScanMetricChip: View {
    let title: String
    let value: Int
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 0) {
                Text("\(value)")
                    .font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(.separator).opacity(0.28), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value)")
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
        .padding(.top, 4)
        .padding(.bottom, 0)
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
                        CategorySummaryTile(summary: summary)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
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
                        ManufacturerSummaryTile(summary: summary)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

private struct SummaryGrid<Content: View>: View {
    private static var cardSpacing: CGFloat { 10 }

    private let content: Content
    private let horizontalOutset: CGFloat

    init(horizontalOutset: CGFloat = 0, @ViewBuilder content: () -> Content) {
        self.horizontalOutset = horizontalOutset
        self.content = content()
    }

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(minimum: 0), spacing: Self.cardSpacing),
                GridItem(.flexible(minimum: 0), spacing: Self.cardSpacing)
            ],
            spacing: Self.cardSpacing
        ) {
            content
        }
        .padding(.horizontal, -horizontalOutset)
        .padding(.top, -2)
        .padding(.bottom, 4)
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

private struct OverviewSummaryTile<Mark: View>: View {
    let count: Int
    let accessibilityLabel: String
    private let mark: Mark

    init(
        count: Int,
        accessibilityLabel: String,
        @ViewBuilder mark: () -> Mark
    ) {
        self.count = count
        self.accessibilityLabel = accessibilityLabel
        self.mark = mark()
    }

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                VStack(spacing: 14) {
                    Text("\(count)")
                        .font(.system(size: 52, weight: .regular, design: .rounded).monospacedDigit())
                        .foregroundStyle(.primary.opacity(0.78))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    mark
                        .frame(height: 36)
                        .frame(maxWidth: .infinity)
                }
                .padding(14)
            }
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(.separator).opacity(0.18), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
    }
}

private struct CategorySummaryTile: View {
    let summary: KnownDeviceCategorySummary

    var body: some View {
        OverviewSummaryTile(
            count: summary.count,
            accessibilityLabel: "\(summary.categoryName), \(summary.count) devices"
        ) {
            Image(systemName: summary.symbolName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(height: 18)
        }
    }
}

private struct ManufacturerSummaryTile: View {
    let summary: KnownDeviceManufacturerSummary

    private var logoAsset: ManufacturerLogoAsset? {
        ManufacturerLogoAsset(manufacturerName: summary.manufacturerName)
    }

    var body: some View {
        OverviewSummaryTile(
            count: summary.count,
            accessibilityLabel: "\(summary.manufacturerName), \(summary.count) devices"
        ) {
            manufacturerMark
        }
    }

    @ViewBuilder
    private var manufacturerMark: some View {
        if let logoAsset {
            Image(logoAsset.imageName)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 135, maxHeight: 36)
                .accessibilityHidden(true)
        } else {
            Text(summary.manufacturerName.uppercased())
                .font(.system(size: 16, weight: .semibold).italic())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .multilineTextAlignment(.center)
        }
    }
}

private struct ManufacturerLogoAsset {
    let imageName: String

    init?(manufacturerName: String, bundle: Bundle = .main) {
        guard let imageName = Self.candidateNames(for: manufacturerName).first(where: { candidate in
            UIImage(named: candidate, in: bundle, compatibleWith: nil) != nil
        }) else {
            return nil
        }

        self.imageName = imageName
    }

    private static func candidateNames(for manufacturerName: String) -> [String] {
        let cleanedName = manufacturerName
            .replacingOccurrences(
                of: #"\b(inc|incorporated|llc|ltd|limited|corp|corporation|company|co|electronics|group)\b\.?"#,
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
            .replacingOccurrences(of: #"[^A-Za-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let words = cleanedName
            .split(separator: " ")
            .map(String.init)

        let fullName = words.joined(separator: " ").localizedCapitalized
        let firstWord = words.first?.localizedCapitalized

        return [fullName, firstWord]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .uniqued()
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}

private struct DeviceRow: View {
    @EnvironmentObject private var appState: AppState

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

#Preview("Live Scan") {
    NavigationStack {
        LiveScanView()
    }
    .environmentObject(AppState.preview)
}
