import SwiftUI

struct LiveScanView: View {
    @Environment(AppState.self) private var appState
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
                    scanner: appState.scanner,
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

#Preview("Live Scan") {
    NavigationStack {
        LiveScanView()
    }
    .environment(AppState.preview)
}
