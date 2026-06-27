import Foundation

struct BluetoothAdvertisementSnapshot: Hashable, Sendable {
    let localName: String?
    let manufacturerCompanyId: Int?
    let appearanceId: Int?
    let serviceUUIDs: [String]
}

struct DetectedDeviceClassification: Hashable, Sendable {
    let manufacturer: String?
    let appearance: String?
    let category: DeviceCategory
    let likelyProduct: String?
    let confidence: Int
    let evidence: [ClassificationEvidence]

    var categoryName: String { category.title }
    var manufacturerName: String? { manufacturer }
    var appearanceName: String? { appearance }
    var symbolName: String { category.symbolName }
}

struct ClassificationEvidence: Hashable, Sendable {
    let source: String
    let value: String
    let confidenceContribution: Int
}

enum DeviceCategory: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case phone
    case watch
    case headphones
    case computer
    case wearable
    case health
    case keyboard
    case mouse
    case tracker
    case vehicle
    case tv
    case lighting
    case unknown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .phone:
            return "Phone"
        case .watch:
            return "Watch"
        case .headphones:
            return "Headphones"
        case .computer:
            return "Computer"
        case .wearable:
            return "Wearable"
        case .health:
            return "Health"
        case .keyboard:
            return "Keyboard"
        case .mouse:
            return "Mouse"
        case .tracker:
            return "Trackers"
        case .vehicle:
            return "Vehicle"
        case .tv:
            return "Television"
        case .lighting:
            return "Lighting"
        case .unknown:
            return "-"
        }
    }

    var symbolName: String {
        switch self {
        case .phone:
            return "iphone"
        case .watch, .wearable:
            return "applewatch"
        case .headphones:
            return "headphones"
        case .computer:
            return "laptopcomputer"
        case .health:
            return "cross.case"
        case .keyboard:
            return "keyboard"
        case .mouse:
            return "computermouse"
        case .tracker:
            return "location"
        case .vehicle:
            return "car"
        case .tv:
            return "tv"
        case .lighting:
            return "lightbulb"
        case .unknown:
            return "sensor.tag.radiowaves.forward"
        }
    }

    var canAnchorGroup: Bool {
        switch self {
        case .phone, .watch, .tv, .wearable:
            return true
        case .headphones, .computer, .health, .keyboard, .mouse, .tracker, .vehicle, .lighting, .unknown:
            return false
        }
    }

    static func infer(for device: BluetoothDevice, observations: [ScanObservation]) -> DeviceCategory {
        let snapshot = BluetoothAdvertisementSnapshot(
            localName: device.localAlias ?? device.advertisedName ?? device.displayName,
            manufacturerCompanyId: observations
                .sorted { $0.timestamp > $1.timestamp }
                .lazy
                .compactMap { Int($0.manufacturerIdentifier ?? "", radix: 16) }
                .first,
            appearanceId: observations
                .sorted { $0.timestamp > $1.timestamp }
                .lazy
                .compactMap(\.appearanceValue)
                .first,
            serviceUUIDs: observations.flatMap(\.serviceUUIDs)
        )

        return DeviceClassifier(
            manufacturerLookup: .empty,
            appearanceLookup: .empty
        )
        .classify(snapshot)
        .category
    }
}

struct KnownDeviceCategorySummary: Identifiable, Hashable, Sendable {
    let categoryName: String
    let symbolName: String
    let count: Int
    let lastSeen: Date?

    var id: String { categoryName }
}

struct KnownDeviceManufacturerSummary: Identifiable, Hashable, Sendable {
    let manufacturerName: String
    let count: Int

    var id: String { manufacturerName }
}
