import Foundation

struct BluetoothDevice: Identifiable, Codable, Hashable {
    let id: String
    var displayName: String?
    var advertisedName: String?
    var firstSeen: Date
    var lastSeen: Date
    var isIgnored: Bool
    var isMyDevice: Bool
    var localAlias: String?
}

struct ScanObservation: Identifiable, Codable, Hashable {
    let id: UUID
    let deviceId: String
    let timestamp: Date
    let rssi: Int
    let advertisedName: String?
    let serviceUUIDs: [String]
    let manufacturerDataSummary: String?
    let manufacturerIdentifier: String?
    let appearanceValue: Int?
    let txPower: Int?
}

struct ScanSession: Identifiable, Codable, Hashable {
    let id: UUID
    let startedAt: Date
    var endedAt: Date?
    var deviceIds: Set<String>
}

struct DeviceCluster: Identifiable, Codable, Hashable {
    let id: UUID
    var deviceIds: [String]
    var clusterType: ClusterType
    var confidenceScore: Double
    var confidenceLabel: ConfidenceLabel
    var seenTogetherCount: Int
    var firstSeen: Date
    var lastSeen: Date
    var reasons: [String]
}

enum ClusterType: String, Codable {
    case singleDevice
    case commonlySeenTogether
}

enum ConfidenceLabel: String, Codable {
    case low
    case medium
    case high
}

enum DistanceCategory: String {
    case close = "Close"
    case nearby = "Nearby"
    case far = "Far"
    case weak = "Weak"
    case unknown = "Unknown"

    init(rssi: Int?) {
        guard let rssi else {
            self = .unknown
            return
        }

        switch rssi {
        case (-55)...:
            self = .close
        case -70 ... -56:
            self = .nearby
        case -85 ... -71:
            self = .far
        default:
            self = .weak
        }
    }
}

enum DeviceCategory: String, Codable, CaseIterable, Identifiable {
    case phone
    case headphones
    case tv
    case watch
    case computer
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .phone:
            return "Phones"
        case .headphones:
            return "Headphones"
        case .tv:
            return "TVs"
        case .watch:
            return "Watches"
        case .computer:
            return "Computers"
        case .other:
            return "Other BLE"
        }
    }

    var symbolName: String {
        switch self {
        case .phone:
            return "iphone"
        case .headphones:
            return "headphones"
        case .tv:
            return "tv"
        case .watch:
            return "applewatch"
        case .computer:
            return "laptopcomputer"
        case .other:
            return "sensor.tag.radiowaves.forward"
        }
    }

    var canAnchorGroup: Bool {
        switch self {
        case .phone, .tv, .watch:
            return true
        case .headphones, .computer, .other:
            return false
        }
    }

    static func infer(for device: BluetoothDevice, observations: [ScanObservation]) -> DeviceCategory {
        let nameText = [
            device.displayName,
            device.advertisedName,
            device.localAlias
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")
        let services = observations.flatMap(\.serviceUUIDs).map { $0.lowercased() }

        if nameText.contains("myphone") ||
            nameText.contains("iphone") ||
            nameText.contains("phone") ||
            nameText.contains("android") ||
            nameText.contains("pixel") ||
            nameText.contains("galaxy") ||
            services.contains("fd6f") ||
            services.contains("fe9f") {
            return .phone
        }

        if nameText.contains("airpods") ||
            nameText.contains("headphone") ||
            nameText.contains("headset") ||
            nameText.contains("buds") ||
            nameText.contains("beats") {
            return .headphones
        }

        if nameText.contains("tv") ||
            nameText.contains("roku") ||
            nameText.contains("chromecast") ||
            nameText.contains("bravia") ||
            nameText.contains("samsung tv") ||
            nameText.contains("lg webos") {
            return .tv
        }

        if nameText.contains("watch") ||
            nameText.contains("fitbit") ||
            nameText.contains("garmin") {
            return .watch
        }

        if nameText.contains("macbook") ||
            nameText.contains("ipad") ||
            nameText.contains("laptop") ||
            nameText.contains("computer") ||
            nameText.contains("pc") {
            return .computer
        }

        return .other
    }
}

struct DeviceCategorySummary: Identifiable, Hashable {
    let category: DeviceCategory
    let count: Int
    let lastSeen: Date?

    var id: DeviceCategory { category }
}

struct AppDataSnapshot: Codable {
    var devices: [BluetoothDevice]
    var observations: [ScanObservation]
    var sessions: [ScanSession]

    static let empty = AppDataSnapshot(devices: [], observations: [], sessions: [])
}
