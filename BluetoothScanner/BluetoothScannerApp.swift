import SwiftUI

@main
struct BluetoothScannerApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            AppView()
                .environmentObject(appState)
                .task {
                    await appState.load()
                }
        }
    }
}

struct AppView: View {
    enum Tab {
        case live
        case groups
        case settings
    }

    @State private var selectedTab: Tab = .live

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                LiveScanView()
            }
            .tabItem {
                Label("Live Scan", systemImage: "dot.radiowaves.left.and.right")
            }
            .tag(Tab.live)

            NavigationStack {
                DeviceGroupsView()
            }
            .tabItem {
                Label("Groups", systemImage: "rectangle.3.group")
            }
            .tag(Tab.groups)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(Tab.settings)
        }
    }
}
