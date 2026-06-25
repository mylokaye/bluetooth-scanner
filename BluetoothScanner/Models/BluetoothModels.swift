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

struct AppDataSnapshot: Codable {
    var devices: [BluetoothDevice]
    var observations: [ScanObservation]
    var sessions: [ScanSession]

    static let empty = AppDataSnapshot(devices: [], observations: [], sessions: [])
}
