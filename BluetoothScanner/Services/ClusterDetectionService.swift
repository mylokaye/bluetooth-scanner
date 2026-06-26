import CryptoKit
import Foundation

struct ClusterDetectionService {
    func detectClusters(
        devices: [BluetoothDevice],
        observations: [ScanObservation],
        sessions: [ScanSession]
    ) -> [DeviceCluster] {
        let activeDevices = devices.filter { !$0.isIgnored }
        let observationsByDevice = Dictionary(grouping: observations, by: \.deviceId)
        let anchorDevices = activeDevices.filter { device in
            DeviceCategory.infer(for: device, observations: observationsByDevice[device.id] ?? []).canAnchorGroup
        }

        var clusters: [DeviceCluster] = []
        var coveredDeviceIds: Set<String> = []

        for anchorDevice in anchorDevices {
            guard !coveredDeviceIds.contains(anchorDevice.id) else { continue }

            let related = relatedDevices(
                to: anchorDevice,
                within: activeDevices,
                observationsByDevice: observationsByDevice,
                sessions: sessions
            )

            if related.isEmpty {
                clusters.append(singleDeviceCluster(for: anchorDevice))
                coveredDeviceIds.insert(anchorDevice.id)
            } else {
                let members = ([anchorDevice] + related).sorted { displayName($0) < displayName($1) }
                let memberIds = members.map(\.id)
                let seenTogetherCount = coPresenceCount(for: memberIds, sessions: sessions)
                let score = confidenceScore(
                    anchorDevice: anchorDevice,
                    related: related,
                    observationsByDevice: observationsByDevice,
                    seenTogetherCount: seenTogetherCount
                )

                clusters.append(
                    DeviceCluster(
                        id: stableClusterId(deviceIds: memberIds),
                        deviceIds: memberIds,
                        clusterType: .commonlySeenTogether,
                        confidenceScore: score,
                        confidenceLabel: confidenceLabel(for: score),
                        seenTogetherCount: max(seenTogetherCount, 2),
                        firstSeen: members.map(\.firstSeen).min() ?? anchorDevice.firstSeen,
                        lastSeen: members.map(\.lastSeen).max() ?? anchorDevice.lastSeen,
                        reasons: [
                            "These devices are commonly seen together.",
                            "The group includes at least one phone, TV, or watch.",
                            "Their RSSI distance categories are similar enough to suggest shared proximity.",
                            "This device appears repeatedly and broadcasts a stable identifier.",
                            "It may be trackable over time by nearby Bluetooth scanners."
                        ]
                    )
                )
                coveredDeviceIds.formUnion(memberIds)
            }
        }

        for anchorDevice in anchorDevices where !coveredDeviceIds.contains(anchorDevice.id) {
            clusters.append(singleDeviceCluster(for: anchorDevice))
        }

        return clusters.sorted {
            if $0.clusterType != $1.clusterType {
                return $0.clusterType == .commonlySeenTogether
            }
            return $0.lastSeen > $1.lastSeen
        }
    }

    private func singleDeviceCluster(for device: BluetoothDevice) -> DeviceCluster {
        DeviceCluster(
            id: stableClusterId(deviceIds: [device.id]),
            deviceIds: [device.id],
            clusterType: .singleDevice,
            confidenceScore: 0.2,
            confidenceLabel: .low,
            seenTogetherCount: 1,
            firstSeen: device.firstSeen,
            lastSeen: device.lastSeen,
            reasons: [
                "No strong related devices have been detected yet.",
                "This device appears repeatedly and broadcasts a stable identifier.",
                "It may be trackable over time by nearby Bluetooth scanners."
            ]
        )
    }

    private func relatedDevices(
        to anchorDevice: BluetoothDevice,
        within devices: [BluetoothDevice],
        observationsByDevice: [String: [ScanObservation]],
        sessions: [ScanSession]
    ) -> [BluetoothDevice] {
        devices
            .filter { $0.id != anchorDevice.id }
            .compactMap { device -> (BluetoothDevice, Int)? in
                let coPresence = coPresenceCount(for: [anchorDevice.id, device.id], sessions: sessions)
                let isStrong = coPresence >= 2
                return isStrong ? (device, coPresence) : nil
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    private func confidenceScore(
        anchorDevice: BluetoothDevice,
        related: [BluetoothDevice],
        observationsByDevice: [String: [ScanObservation]],
        seenTogetherCount: Int
    ) -> Double {
        let repeatedCoPresence = min(Double(seenTogetherCount) / 8.0, 0.45)
        let timingScore = related
            .map { timingSimilarityScore(observationsByDevice[anchorDevice.id] ?? [], observationsByDevice[$0.id] ?? []) }
            .max() ?? 0

        return min(0.95, 0.2 + repeatedCoPresence + (timingScore * 0.15))
    }

    private func confidenceLabel(for score: Double) -> ConfidenceLabel {
        if score >= 0.7 {
            return .high
        } else if score >= 0.45 {
            return .medium
        } else {
            return .low
        }
    }

    private func coPresenceCount(for deviceIds: [String], sessions: [ScanSession]) -> Int {
        sessions.filter { session in
            deviceIds.allSatisfy { session.deviceIds.contains($0) }
        }.count
    }

    private func timingSimilarityScore(_ lhs: [ScanObservation], _ rhs: [ScanObservation]) -> Double {
        guard let leftFirst = lhs.map(\.timestamp).min(),
              let rightFirst = rhs.map(\.timestamp).min(),
              let leftLast = lhs.map(\.timestamp).max(),
              let rightLast = rhs.map(\.timestamp).max()
        else { return 0 }

        let arrivalGap = abs(leftFirst.timeIntervalSince(rightFirst))
        let departureGap = abs(leftLast.timeIntervalSince(rightLast))
        let combinedGap = arrivalGap + departureGap
        return max(0, 1 - (combinedGap / 120.0))
    }

    private func displayName(_ device: BluetoothDevice) -> String {
        device.localAlias ?? device.displayName ?? device.advertisedName ?? "Unknown BLE Device"
    }

    private func stableClusterId(deviceIds: [String]) -> UUID {
        let key = deviceIds.sorted().joined(separator: "|")
        let digest = SHA256.hash(data: Data(key.utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80

        return bytes.withUnsafeBufferPointer { buffer in
            UUID(uuidString: NSUUID(uuidBytes: buffer.baseAddress!).uuidString) ?? UUID()
        }
    }
}
