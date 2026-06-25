import Foundation

struct ClusterDetectionService {
    func detectClusters(
        devices: [BluetoothDevice],
        observations: [ScanObservation],
        sessions: [ScanSession]
    ) -> [DeviceCluster] {
        let activeDevices = devices.filter { !$0.isIgnored }
        let observationsByDevice = Dictionary(grouping: observations, by: \.deviceId)
        let phoneDevices = activeDevices.filter { isPhoneLike($0, observations: observationsByDevice[$0.id] ?? []) }

        var clusters: [DeviceCluster] = []
        var coveredDeviceIds: Set<String> = []

        for phone in phoneDevices {
            let related = relatedDevices(
                to: phone,
                within: activeDevices,
                observationsByDevice: observationsByDevice,
                sessions: sessions
            )

            if related.isEmpty {
                clusters.append(singleDeviceCluster(for: phone))
                coveredDeviceIds.insert(phone.id)
            } else {
                let members = ([phone] + related).sorted { displayName($0) < displayName($1) }
                let memberIds = members.map(\.id)
                let seenTogetherCount = coPresenceCount(for: memberIds, sessions: sessions)
                let score = confidenceScore(
                    phone: phone,
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
                        firstSeen: members.map(\.firstSeen).min() ?? phone.firstSeen,
                        lastSeen: members.map(\.lastSeen).max() ?? phone.lastSeen,
                        reasons: [
                            "These devices are commonly seen together.",
                            "This device appears repeatedly and broadcasts a stable identifier.",
                            "It may be trackable over time by nearby Bluetooth scanners."
                        ]
                    )
                )
                coveredDeviceIds.formUnion(memberIds)
            }
        }

        for phone in phoneDevices where !coveredDeviceIds.contains(phone.id) {
            clusters.append(singleDeviceCluster(for: phone))
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
        to phone: BluetoothDevice,
        within devices: [BluetoothDevice],
        observationsByDevice: [String: [ScanObservation]],
        sessions: [ScanSession]
    ) -> [BluetoothDevice] {
        devices
            .filter { $0.id != phone.id }
            .compactMap { device -> (BluetoothDevice, Int)? in
                let coPresence = coPresenceCount(for: [phone.id, device.id], sessions: sessions)
                let rssiSimilarity = rssiSimilarityScore(
                    observationsByDevice[phone.id] ?? [],
                    observationsByDevice[device.id] ?? []
                )
                let isStrong = coPresence >= 2 || (coPresence >= 1 && rssiSimilarity > 0.75)
                return isStrong ? (device, coPresence) : nil
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    private func confidenceScore(
        phone: BluetoothDevice,
        related: [BluetoothDevice],
        observationsByDevice: [String: [ScanObservation]],
        seenTogetherCount: Int
    ) -> Double {
        let repeatedCoPresence = min(Double(seenTogetherCount) / 8.0, 0.45)
        let rssiScore = related
            .map { rssiSimilarityScore(observationsByDevice[phone.id] ?? [], observationsByDevice[$0.id] ?? []) }
            .max() ?? 0
        let timingScore = related
            .map { timingSimilarityScore(observationsByDevice[phone.id] ?? [], observationsByDevice[$0.id] ?? []) }
            .max() ?? 0

        return min(0.95, 0.2 + repeatedCoPresence + (rssiScore * 0.2) + (timingScore * 0.15))
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

    private func isPhoneLike(_ device: BluetoothDevice, observations: [ScanObservation]) -> Bool {
        let text = [
            device.displayName,
            device.advertisedName,
            device.localAlias
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")

        if text.contains("iphone") || text.contains("phone") || text.contains("android") {
            return true
        }

        let services = observations.flatMap(\.serviceUUIDs).map { $0.lowercased() }
        return services.contains("fd6f") || services.contains("fe9f") || services.contains("fd5a")
    }

    private func coPresenceCount(for deviceIds: [String], sessions: [ScanSession]) -> Int {
        sessions.filter { session in
            deviceIds.allSatisfy { session.deviceIds.contains($0) }
        }.count
    }

    private func rssiSimilarityScore(_ lhs: [ScanObservation], _ rhs: [ScanObservation]) -> Double {
        guard let leftAverage = averageRSSI(lhs), let rightAverage = averageRSSI(rhs) else { return 0 }
        let difference = abs(leftAverage - rightAverage)
        return max(0, 1 - (difference / 35.0))
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

    private func averageRSSI(_ observations: [ScanObservation]) -> Double? {
        guard !observations.isEmpty else { return nil }
        return Double(observations.map(\.rssi).reduce(0, +)) / Double(observations.count)
    }

    private func displayName(_ device: BluetoothDevice) -> String {
        device.localAlias ?? device.displayName ?? device.advertisedName ?? "Unknown BLE Device"
    }

    private func stableClusterId(deviceIds: [String]) -> UUID {
        let key = deviceIds.sorted().joined(separator: "|")
        return UUID(uuidString: String(key.uuidStringPrefix.prefix(36))) ?? UUID()
    }
}

private extension String {
    var uuidStringPrefix: String {
        let hex = self.unicodeScalars
            .map { String(format: "%02X", $0.value % 255) }
            .joined()
            .padding(toLength: 32, withPad: "0", startingAt: 0)
            .prefix(32)

        let chars = Array(hex)
        return "\(String(chars[0..<8]))-\(String(chars[8..<12]))-\(String(chars[12..<16]))-\(String(chars[16..<20]))-\(String(chars[20..<32]))"
    }
}
