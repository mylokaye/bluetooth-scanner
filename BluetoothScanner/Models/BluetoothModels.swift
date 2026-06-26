import Foundation
import SwiftUI

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

// MARK: - Activity Status

enum ActivityStatus: String, CaseIterable {
    case online
    case recentlySeen
    case offline
}

// MARK: - Relative Time Formatting

extension Date {
    /// Returns a human-friendly relative time string such as "42s ago", "2m ago", or "4m 35s ago".
    func formattedRelative(to date: Date = Date()) -> String {
        let elapsed = max(0, date.timeIntervalSince(self))

        if elapsed < 60 {
            return "\(Int(elapsed))s ago"
        } else if elapsed < 3_600 {
            let minutes = Int(elapsed / 60)
            let seconds = Int(elapsed.truncatingRemainder(dividingBy: 60))
            if seconds == 0 {
                return "\(minutes)m ago"
            } else {
                return "\(minutes)m \(seconds)s ago"
            }
        } else if elapsed < 86_400 {
            let hours = Int(elapsed / 3_600)
            let minutes = Int(elapsed.truncatingRemainder(dividingBy: 3_600) / 60)
            if minutes == 0 {
                return "\(hours)h ago"
            } else {
                return "\(hours)h \(minutes)m ago"
            }
        } else {
            let days = Int(elapsed / 86_400)
            return days == 1 ? "1d ago" : "\(days)d ago"
        }
    }
}

// MARK: - Activity Status UI Helpers

extension ActivityStatus {
    var displayName: String {
        switch self {
        case .online: return "Online"
        case .recentlySeen: return "Recently Seen"
        case .offline: return "Offline"
        }
    }

    var color: Color {
        switch self {
        case .online: return .green
        case .recentlySeen: return .orange
        case .offline: return .gray
        }
    }
}
