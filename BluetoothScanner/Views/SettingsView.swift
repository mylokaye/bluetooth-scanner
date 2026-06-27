import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        List {
            Section {
                ScreenHeader(title: "Settings")
            }
            .listRowInsets(EdgeInsets(top: 54, leading: 16, bottom: 0, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            Section("Scanning") {
                LabeledContent("Mode", value: "While app is open")
                LabeledContent("Connections", value: "Never connects or pairs")
                LabeledContent("Storage", value: "Local JSON")
            }

            if let lastStorageError = appState.lastStorageError {
                Section("Storage Error") {
                    Text(lastStorageError)
                        .foregroundStyle(.red)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

#Preview("Settings") {
    NavigationStack {
        SettingsView()
    }
    .environmentObject(AppState.preview)
}
