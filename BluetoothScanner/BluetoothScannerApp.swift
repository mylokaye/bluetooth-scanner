import SwiftUI

@main
struct BluetoothScannerApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            AppView()
                .environment(appState)
                .task {
                    await appState.load()
                }
        }
    }
}

struct AppView: View {
    enum AppTab {
        case live
        case groups
        case settings
    }

    @State private var selectedTab: AppTab = .live

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Live Scan", systemImage: "dot.radiowaves.left.and.right", value: AppTab.live) {
                NavigationStack {
                    LiveScanView()
                }
            }

            Tab("Groups", systemImage: "rectangle.3.group", value: AppTab.groups) {
                NavigationStack {
                    DeviceGroupsView()
                }
            }

            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                NavigationStack {
                    SettingsView()
                }
            }
        }
    }
}

#Preview("App") {
    AppView()
        .environment(AppState.preview)
}
