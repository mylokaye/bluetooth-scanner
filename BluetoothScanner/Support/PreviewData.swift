import Foundation

enum PreviewData {
    static let now = Date(timeIntervalSinceReferenceDate: 812_000_000)

    static let phone = BluetoothDevice(
        id: "preview-phone",
        displayName: "Mylo's iPhone",
        advertisedName: "iPhone",
        firstSeen: now.addingTimeInterval(-3_600),
        lastSeen: now.addingTimeInterval(-3),
        isMyDevice: false,
        localAlias: nil
    )

    static let watch = BluetoothDevice(
        id: "preview-watch",
        displayName: "Apple Watch",
        advertisedName: "Apple Watch",
        firstSeen: now.addingTimeInterval(-2_900),
        lastSeen: now.addingTimeInterval(-11),
        isMyDevice: false,
        localAlias: nil
    )

    static let headphones = BluetoothDevice(
        id: "preview-airpods",
        displayName: "AirPods Pro",
        advertisedName: "AirPods Pro",
        firstSeen: now.addingTimeInterval(-2_200),
        lastSeen: now.addingTimeInterval(-46),
        isMyDevice: false,
        localAlias: nil
    )

    static let devices = [
        phone,
        watch,
        headphones
    ]

    static let observations = [
        ScanObservation(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
            deviceId: phone.id,
            timestamp: phone.lastSeen,
            rssi: -48,
            advertisedName: phone.advertisedName,
            serviceUUIDs: ["180A"],
            manufacturerDataSummary: "Apple nearby device payload",
            manufacturerIdentifier: "004C",
            appearanceValue: 64,
            txPower: -12
        ),
        ScanObservation(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!,
            deviceId: watch.id,
            timestamp: watch.lastSeen,
            rssi: -61,
            advertisedName: watch.advertisedName,
            serviceUUIDs: ["180D", "180F"],
            manufacturerDataSummary: "Apple watch payload",
            manufacturerIdentifier: "004C",
            appearanceValue: 193,
            txPower: -16
        ),
        ScanObservation(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000103")!,
            deviceId: headphones.id,
            timestamp: headphones.lastSeen,
            rssi: -76,
            advertisedName: headphones.advertisedName,
            serviceUUIDs: ["110B", "110E"],
            manufacturerDataSummary: "Apple audio payload",
            manufacturerIdentifier: "004C",
            appearanceValue: nil,
            txPower: -18
        )
    ]

    static let sessions = [
        ScanSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!,
            startedAt: now.addingTimeInterval(-900),
            endedAt: now.addingTimeInterval(-600),
            deviceIds: [phone.id, watch.id, headphones.id]
        ),
        ScanSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000202")!,
            startedAt: now.addingTimeInterval(-300),
            endedAt: nil,
            deviceIds: [phone.id, watch.id]
        )
    ]

    static let clusters = [
        DeviceCluster(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000301")!,
            deviceIds: [phone.id, watch.id, headphones.id],
            clusterType: .commonlySeenTogether,
            confidenceScore: 0.82,
            confidenceLabel: .high,
            seenTogetherCount: 4,
            firstSeen: phone.firstSeen,
            lastSeen: phone.lastSeen,
            reasons: ["These devices are commonly seen together."]
        )
    ]
}
