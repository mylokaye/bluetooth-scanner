import Foundation

enum PreviewData {
    static let phone = BluetoothDevice(
        id: "preview-phone",
        displayName: "- / Apple Phone",
        advertisedName: "iPhone",
        firstSeen: .now.addingTimeInterval(-3600),
        lastSeen: .now,
        isIgnored: false,
        isMyDevice: false,
        localAlias: nil
    )
}
