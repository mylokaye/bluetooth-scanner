import CryptoKit
import Foundation

struct ClusterDetectionResult: Sendable {
    var clusters: [DeviceCluster]
}

struct ClusterDetectionDeviceSnapshot: Sendable {
    let device: BluetoothDevice
    let category: DeviceCategory
    let latestObservation: ScanObservation
    let firstSeen: Date
    let correlationBuckets: [Int: Double]
    let rollingBuckets: [Int: Double]
    let isStationary: Bool
    let medianRSSI: Double?
}

actor ClusterDetectionWorker {
    private let service = ClusterDetectionService()

    func reset() {
        service.reset()
    }

    func detectClusters(
        snapshots: [ClusterDetectionDeviceSnapshot],
        at date: Date = Date()
    ) -> ClusterDetectionResult {
        service.detectClusters(snapshots: snapshots, at: date)
    }
}

final class ClusterDetectionService {
    private struct PendingAssignment {
        var anchorId: String
        var cycleCount: Int
    }

    private let rollingHistoryWindow: TimeInterval = 30
    private let correlationWindow: TimeInterval = 20
    private let staleDeviceInterval: TimeInterval = 30
    private let minimumOverlapCount = 5
    private let minimumCorrelation = 0.7
    private let minimumUniquenessMargin = 0.2
    private let switchHysteresisCycles = 3
    private let confidenceSmoothingAlpha = 0.3
    private let stationaryVarianceThreshold = 2.0
    private let rssiFloor = -100
    private let ownerStrongCorrelation = 0.8
    private let ownerMinimumCycles = 3
    private let ownerCloseRSSIThreshold = -50.0
    private let ownerSingleDeviceConfidenceMultiplier = 0.4
    private let ownerSingleDeviceConfidenceCap = 0.4
    private let phoneBaseConfidence = 0.25
    private let ownerBaseConfidence = 0.2
    private let ownerConfidenceCap = 0.82
    private let ownerAnchorId = "__owner_group__"

    private var stableAssignmentsByDeviceId: [String: String] = [:]
    private var pendingAssignmentsByDeviceId: [String: PendingAssignment] = [:]
    private var smoothedCorrelationByPairKey: [String: Double] = [:]
    private var ownerCandidateCycleCount = 0
    private var ownerCandidateKey: String?

    func reset() {
        stableAssignmentsByDeviceId = [:]
        pendingAssignmentsByDeviceId = [:]
        smoothedCorrelationByPairKey = [:]
        ownerCandidateCycleCount = 0
        ownerCandidateKey = nil
    }

    func detectClusters(
        devices: [BluetoothDevice],
        observationsByDevice: [String: [ScanObservation]],
        classificationsByDevice: [String: DetectedDeviceClassification],
        at date: Date = Date()
    ) -> ClusterDetectionResult {
        let activeDevices = devices.filter { device in
            guard let latestObservation = latestValidObservation(
                for: device.id,
                observationsByDevice: observationsByDevice
            ) else { return false }

            return date.timeIntervalSince(latestObservation.timestamp) <= staleDeviceInterval
        }

        let phones = activeDevices.filter { device in
            classificationsByDevice[device.id]?.category == .phone
        }
        let personalDevices = activeDevices.filter { device in
            guard classificationsByDevice[device.id]?.category != .phone else { return false }
            return personalDeviceWeight(for: classificationsByDevice[device.id]?.category) != nil
        }
        let eligiblePersonalDevices = personalDevices.filter { device in
            !isStationaryDevice(
                deviceId: device.id,
                observationsByDevice: observationsByDevice,
                at: date
            )
        }

        let correlationBuckets = activeDevices.reduce(into: [String: [Int: Double]]()) { result, device in
            result[device.id] = rssiBuckets(
                for: observationsByDevice[device.id] ?? [],
                since: date.addingTimeInterval(-correlationWindow)
            )
        }
        let rollingBuckets = activeDevices.reduce(into: [String: [Int: Double]]()) { result, device in
            result[device.id] = rssiBuckets(
                for: observationsByDevice[device.id] ?? [],
                since: date.addingTimeInterval(-rollingHistoryWindow)
            )
        }

        let correlationsByDevice = pairwisePhoneCorrelations(
            phones: phones,
            personalDevices: eligiblePersonalDevices,
            bucketsByDeviceId: correlationBuckets
        )
        let assignments = stableAssignments(
            for: eligiblePersonalDevices,
            correlationsByDevice: correlationsByDevice
        )

        var clusters = phoneClusters(
            phones: phones,
            assignments: assignments,
            correlationsByDevice: correlationsByDevice,
            classificationsByDevice: classificationsByDevice,
            observationsByDevice: observationsByDevice
        )

        if let ownerCluster = ownerCluster(
            from: personalDevices.filter { assignments[$0.id] == nil },
            bucketsByDeviceId: rollingBuckets,
            observationsByDevice: observationsByDevice,
            classificationsByDevice: classificationsByDevice,
            at: date
        ) {
            clusters.append(ownerCluster)
        }

        return ClusterDetectionResult(
            clusters: clusters.sorted(by: clusterSort)
        )
    }

    func detectClusters(
        snapshots: [ClusterDetectionDeviceSnapshot],
        at date: Date = Date()
    ) -> ClusterDetectionResult {
        let activeSnapshots = snapshots.filter { snapshot in
            date.timeIntervalSince(snapshot.latestObservation.timestamp) <= staleDeviceInterval
        }
        let snapshotsByDeviceId = Dictionary(
            uniqueKeysWithValues: activeSnapshots.map { ($0.device.id, $0) }
        )

        let phones = activeSnapshots
            .filter { $0.category == .phone }
            .map(\.device)
        let personalDevices = activeSnapshots
            .filter { $0.category != .phone && personalDeviceWeight(for: $0.category) != nil }
            .map(\.device)
        let eligiblePersonalDevices = activeSnapshots
            .filter { $0.category != .phone && personalDeviceWeight(for: $0.category) != nil && !$0.isStationary }
            .map(\.device)

        let correlationBuckets = Dictionary(
            uniqueKeysWithValues: activeSnapshots.map { ($0.device.id, $0.correlationBuckets) }
        )
        let rollingBuckets = Dictionary(
            uniqueKeysWithValues: activeSnapshots.map { ($0.device.id, $0.rollingBuckets) }
        )
        let classificationsByDevice = Dictionary(
            uniqueKeysWithValues: activeSnapshots.map {
                ($0.device.id, DetectedDeviceClassification.placeholder(category: $0.category))
            }
        )

        let correlationsByDevice = pairwisePhoneCorrelations(
            phones: phones,
            personalDevices: eligiblePersonalDevices,
            bucketsByDeviceId: correlationBuckets
        )
        let assignments = stableAssignments(
            for: eligiblePersonalDevices,
            correlationsByDevice: correlationsByDevice
        )

        var clusters = phoneClusters(
            phones: phones,
            assignments: assignments,
            correlationsByDevice: correlationsByDevice,
            classificationsByDevice: classificationsByDevice,
            snapshotsByDeviceId: snapshotsByDeviceId
        )

        if let ownerCluster = ownerCluster(
            from: personalDevices.filter { assignments[$0.id] == nil },
            bucketsByDeviceId: rollingBuckets,
            snapshotsByDeviceId: snapshotsByDeviceId,
            classificationsByDevice: classificationsByDevice,
            at: date
        ) {
            clusters.append(ownerCluster)
        }

        return ClusterDetectionResult(
            clusters: clusters.sorted(by: clusterSort)
        )
    }

    private func pairwisePhoneCorrelations(
        phones: [BluetoothDevice],
        personalDevices: [BluetoothDevice],
        bucketsByDeviceId: [String: [Int: Double]]
    ) -> [String: [(phoneId: String, correlation: Double)]] {
        personalDevices.reduce(into: [String: [(phoneId: String, correlation: Double)]]()) { result, device in
            let deviceBuckets = bucketsByDeviceId[device.id] ?? [:]
            result[device.id] = phones
                .map { phone in
                    (
                        phoneId: phone.id,
                        correlation: pearsonCorrelation(
                            lhs: deviceBuckets,
                            rhs: bucketsByDeviceId[phone.id] ?? [:]
                        )
                    )
                }
                .sorted { $0.correlation > $1.correlation }
        }
    }

    private func stableAssignments(
        for personalDevices: [BluetoothDevice],
        correlationsByDevice: [String: [(phoneId: String, correlation: Double)]]
    ) -> [String: String] {
        var assignments: [String: String] = [:]
        let activeDeviceIds = Set(personalDevices.map(\.id))

        stableAssignmentsByDeviceId = stableAssignmentsByDeviceId.filter { activeDeviceIds.contains($0.key) }
        pendingAssignmentsByDeviceId = pendingAssignmentsByDeviceId.filter { activeDeviceIds.contains($0.key) }

        for device in personalDevices {
            let proposedAnchorId = proposedAssignment(from: correlationsByDevice[device.id] ?? [])
            let currentAnchorId = stableAssignmentsByDeviceId[device.id]

            if proposedAnchorId == currentAnchorId {
                pendingAssignmentsByDeviceId[device.id] = nil
            } else if currentAnchorId == nil {
                stableAssignmentsByDeviceId[device.id] = proposedAnchorId
                pendingAssignmentsByDeviceId[device.id] = nil
            } else if let proposedAnchorId {
                var pending = pendingAssignmentsByDeviceId[device.id]
                    ?? PendingAssignment(anchorId: proposedAnchorId, cycleCount: 0)

                if pending.anchorId == proposedAnchorId {
                    pending.cycleCount += 1
                } else {
                    pending = PendingAssignment(anchorId: proposedAnchorId, cycleCount: 1)
                }

                if pending.cycleCount >= switchHysteresisCycles {
                    stableAssignmentsByDeviceId[device.id] = proposedAnchorId
                    pendingAssignmentsByDeviceId[device.id] = nil
                } else {
                    pendingAssignmentsByDeviceId[device.id] = pending
                }
            } else {
                stableAssignmentsByDeviceId[device.id] = nil
                pendingAssignmentsByDeviceId[device.id] = nil
            }

            if let anchorId = stableAssignmentsByDeviceId[device.id] {
                assignments[device.id] = anchorId
            }
        }

        return assignments
    }

    private func proposedAssignment(from correlations: [(phoneId: String, correlation: Double)]) -> String? {
        guard let best = correlations.first,
              best.correlation > minimumCorrelation
        else { return nil }

        let secondBest = correlations.dropFirst().first?.correlation ?? 0
        guard best.correlation - secondBest > minimumUniquenessMargin else { return nil }

        return best.phoneId
    }

    private func phoneClusters(
        phones: [BluetoothDevice],
        assignments: [String: String],
        correlationsByDevice: [String: [(phoneId: String, correlation: Double)]],
        classificationsByDevice: [String: DetectedDeviceClassification],
        observationsByDevice: [String: [ScanObservation]]
    ) -> [DeviceCluster] {
        phones.map { phone in
            let assignedDeviceIds = cappedAssignedDeviceIds(
                for: phone.id,
                assignments: assignments,
                correlationsByDevice: correlationsByDevice,
                classificationsByDevice: classificationsByDevice
            )
            let memberIds = ([phone.id] + assignedDeviceIds).sorted()
            let assignedConfidence = assignedDeviceIds.reduce(0.0) { partial, deviceId in
                let category = classificationsByDevice[deviceId]?.category
                let weight = personalDeviceWeight(for: category) ?? 0
                let correlation = correlationsByDevice[deviceId]?
                    .first { $0.phoneId == phone.id }?
                    .correlation ?? 0
                return partial + (weight * smoothedCorrelation(for: deviceId, anchorId: phone.id, correlation: correlation))
            }
            let confidence = min(1, phoneBaseConfidence + assignedConfidence)
            let devicesLastSeen = memberIds.compactMap { latestValidObservation(for: $0, observationsByDevice: observationsByDevice)?.timestamp }
            let firstSeen = memberIds.compactMap { deviceId in
                observationsByDevice[deviceId]?.map(\.timestamp).min()
            }.min() ?? phone.firstSeen
            let lastSeen = devicesLastSeen.max() ?? phone.lastSeen

            return DeviceCluster(
                id: stableClusterId(key: "phone:\(phone.id)"),
                deviceIds: memberIds,
                anchorDeviceId: phone.id,
                clusterType: assignedDeviceIds.isEmpty ? .singleDevice : .commonlySeenTogether,
                confidenceScore: confidence,
                confidenceLabel: confidenceLabel(for: confidence),
                seenTogetherCount: max(1, memberIds.count),
                firstSeen: firstSeen,
                lastSeen: lastSeen,
                isOwnerGroup: false,
                reasons: reasons(for: assignedDeviceIds.isEmpty, isOwnerGroup: false)
            )
        }
    }

    private func phoneClusters(
        phones: [BluetoothDevice],
        assignments: [String: String],
        correlationsByDevice: [String: [(phoneId: String, correlation: Double)]],
        classificationsByDevice: [String: DetectedDeviceClassification],
        snapshotsByDeviceId: [String: ClusterDetectionDeviceSnapshot]
    ) -> [DeviceCluster] {
        phones.map { phone in
            let assignedDeviceIds = cappedAssignedDeviceIds(
                for: phone.id,
                assignments: assignments,
                correlationsByDevice: correlationsByDevice,
                classificationsByDevice: classificationsByDevice
            )
            let memberIds = ([phone.id] + assignedDeviceIds).sorted()
            let assignedConfidence = assignedDeviceIds.reduce(0.0) { partial, deviceId in
                let category = classificationsByDevice[deviceId]?.category
                let weight = personalDeviceWeight(for: category) ?? 0
                let correlation = correlationsByDevice[deviceId]?
                    .first { $0.phoneId == phone.id }?
                    .correlation ?? 0
                return partial + (weight * smoothedCorrelation(for: deviceId, anchorId: phone.id, correlation: correlation))
            }
            let confidence = min(1, phoneBaseConfidence + assignedConfidence)
            let firstSeen = memberIds.compactMap { snapshotsByDeviceId[$0]?.firstSeen }.min() ?? phone.firstSeen
            let lastSeen = memberIds.compactMap { snapshotsByDeviceId[$0]?.latestObservation.timestamp }.max() ?? phone.lastSeen

            return DeviceCluster(
                id: stableClusterId(key: "phone:\(phone.id)"),
                deviceIds: memberIds,
                anchorDeviceId: phone.id,
                clusterType: assignedDeviceIds.isEmpty ? .singleDevice : .commonlySeenTogether,
                confidenceScore: confidence,
                confidenceLabel: confidenceLabel(for: confidence),
                seenTogetherCount: max(1, memberIds.count),
                firstSeen: firstSeen,
                lastSeen: lastSeen,
                isOwnerGroup: false,
                reasons: reasons(for: assignedDeviceIds.isEmpty, isOwnerGroup: false)
            )
        }
    }

    private func cappedAssignedDeviceIds(
        for phoneId: String,
        assignments: [String: String],
        correlationsByDevice: [String: [(phoneId: String, correlation: Double)]],
        classificationsByDevice: [String: DetectedDeviceClassification]
    ) -> [String] {
        var selectedByCategory: [DeviceCategory: (deviceId: String, correlation: Double)] = [:]

        for (deviceId, assignedPhoneId) in assignments where assignedPhoneId == phoneId {
            guard let category = classificationsByDevice[deviceId]?.category,
                  category == .watch || category == .headphones
            else { continue }

            let correlation = correlationsByDevice[deviceId]?
                .first { $0.phoneId == phoneId }?
                .correlation ?? 0
            let current = selectedByCategory[category]
            let currentCorrelation = current?.correlation ?? -Double.infinity

            if correlation > currentCorrelation {
                selectedByCategory[category] = (deviceId, correlation)
            }
        }

        return [
            selectedByCategory[.watch]?.deviceId,
            selectedByCategory[.headphones]?.deviceId
        ]
        .compactMap { $0 }
        .sorted()
    }

    private func ownerCluster(
        from devices: [BluetoothDevice],
        bucketsByDeviceId: [String: [Int: Double]],
        observationsByDevice: [String: [ScanObservation]],
        classificationsByDevice: [String: DetectedDeviceClassification],
        at date: Date
    ) -> DeviceCluster? {
        let closeDevices = devices
            .filter { medianRSSI(for: observationsByDevice[$0.id] ?? [], since: date.addingTimeInterval(-rollingHistoryWindow)) ?? -Double.infinity > ownerCloseRSSIThreshold }
            .sorted { $0.id < $1.id }
        let cappedCloseDevices = cappedOwnerDevices(
            from: closeDevices,
            observationsByDevice: observationsByDevice,
            classificationsByDevice: classificationsByDevice
        )

        guard !cappedCloseDevices.isEmpty else {
            resetOwnerCandidate()
            return nil
        }

        let averageCorrelation: Double?
        if cappedCloseDevices.count == 1 {
            averageCorrelation = nil
        } else {
            let pairCorrelations = pairwiseCorrelations(
                deviceIds: cappedCloseDevices.map(\.id),
                bucketsByDeviceId: bucketsByDeviceId
            )
            let candidateAverageCorrelation = pairCorrelations.isEmpty
                ? 0
                : pairCorrelations.reduce(0, +) / Double(pairCorrelations.count)

            guard candidateAverageCorrelation > ownerStrongCorrelation else {
                resetOwnerCandidate()
                return nil
            }
            averageCorrelation = candidateAverageCorrelation
        }

        updateOwnerCandidateCycleCount(for: cappedCloseDevices)

        guard ownerCandidateCycleCount >= ownerMinimumCycles else {
            return nil
        }

        let confidence = ownerConfidence(
            for: cappedCloseDevices,
            classificationsByDevice: classificationsByDevice,
            averageCorrelation: averageCorrelation
        )

        return DeviceCluster(
            id: stableClusterId(key: "owner"),
            deviceIds: cappedCloseDevices.map(\.id),
            anchorDeviceId: nil,
            clusterType: .ownerPersonalDevices,
            confidenceScore: confidence,
            confidenceLabel: confidenceLabel(for: confidence),
            seenTogetherCount: cappedCloseDevices.count,
            firstSeen: cappedCloseDevices.map(\.firstSeen).min() ?? date,
            lastSeen: cappedCloseDevices.map(\.lastSeen).max() ?? date,
            isOwnerGroup: true,
            reasons: reasons(for: false, isOwnerGroup: true, memberCount: cappedCloseDevices.count)
        )
    }

    private func ownerCluster(
        from devices: [BluetoothDevice],
        bucketsByDeviceId: [String: [Int: Double]],
        snapshotsByDeviceId: [String: ClusterDetectionDeviceSnapshot],
        classificationsByDevice: [String: DetectedDeviceClassification],
        at date: Date
    ) -> DeviceCluster? {
        let closeDevices = devices
            .filter { (snapshotsByDeviceId[$0.id]?.medianRSSI ?? -Double.infinity) > ownerCloseRSSIThreshold }
            .sorted { $0.id < $1.id }
        let cappedCloseDevices = cappedOwnerDevices(
            from: closeDevices,
            snapshotsByDeviceId: snapshotsByDeviceId,
            classificationsByDevice: classificationsByDevice
        )

        guard !cappedCloseDevices.isEmpty else {
            resetOwnerCandidate()
            return nil
        }

        let averageCorrelation: Double?
        if cappedCloseDevices.count == 1 {
            averageCorrelation = nil
        } else {
            let pairCorrelations = pairwiseCorrelations(
                deviceIds: cappedCloseDevices.map(\.id),
                bucketsByDeviceId: bucketsByDeviceId
            )
            let candidateAverageCorrelation = pairCorrelations.isEmpty
                ? 0
                : pairCorrelations.reduce(0, +) / Double(pairCorrelations.count)

            guard candidateAverageCorrelation > ownerStrongCorrelation else {
                resetOwnerCandidate()
                return nil
            }
            averageCorrelation = candidateAverageCorrelation
        }

        updateOwnerCandidateCycleCount(for: cappedCloseDevices)

        guard ownerCandidateCycleCount >= ownerMinimumCycles else {
            return nil
        }

        let confidence = ownerConfidence(
            for: cappedCloseDevices,
            classificationsByDevice: classificationsByDevice,
            averageCorrelation: averageCorrelation
        )

        return DeviceCluster(
            id: stableClusterId(key: "owner"),
            deviceIds: cappedCloseDevices.map(\.id),
            anchorDeviceId: nil,
            clusterType: .ownerPersonalDevices,
            confidenceScore: confidence,
            confidenceLabel: confidenceLabel(for: confidence),
            seenTogetherCount: cappedCloseDevices.count,
            firstSeen: cappedCloseDevices.compactMap { snapshotsByDeviceId[$0.id]?.firstSeen }.min() ?? date,
            lastSeen: cappedCloseDevices.compactMap { snapshotsByDeviceId[$0.id]?.latestObservation.timestamp }.max() ?? date,
            isOwnerGroup: true,
            reasons: reasons(for: false, isOwnerGroup: true, memberCount: cappedCloseDevices.count)
        )
    }

    private func updateOwnerCandidateCycleCount(for devices: [BluetoothDevice]) {
        let candidateKey = devices.map(\.id).sorted().joined(separator: "|")
        if ownerCandidateKey == candidateKey {
            ownerCandidateCycleCount += 1
        } else {
            ownerCandidateKey = candidateKey
            ownerCandidateCycleCount = 1
        }
    }

    private func resetOwnerCandidate() {
        ownerCandidateKey = nil
        ownerCandidateCycleCount = 0
    }

    private func ownerConfidence(
        for devices: [BluetoothDevice],
        classificationsByDevice: [String: DetectedDeviceClassification],
        averageCorrelation: Double?
    ) -> Double {
        if devices.count == 1 {
            let category = classificationsByDevice[devices[0].id]?.category
            let weight = personalDeviceWeight(for: category) ?? 0
            return min(
                ownerSingleDeviceConfidenceCap,
                ownerBaseConfidence + (weight * ownerSingleDeviceConfidenceMultiplier)
            )
        }

        let correlation = averageCorrelation ?? 0
        let confidenceBonus = devices.reduce(0.0) { partial, device in
            let category = classificationsByDevice[device.id]?.category
            let weight = personalDeviceWeight(for: category) ?? 0
            return partial + (weight * smoothedCorrelation(
                for: device.id,
                anchorId: ownerAnchorId,
                correlation: correlation
            ))
        }
        return min(ownerConfidenceCap, ownerBaseConfidence + confidenceBonus)
    }

    private func cappedOwnerDevices(
        from devices: [BluetoothDevice],
        observationsByDevice: [String: [ScanObservation]],
        classificationsByDevice: [String: DetectedDeviceClassification]
    ) -> [BluetoothDevice] {
        let bestWatch = bestDevice(
            in: devices,
            category: .watch,
            observationsByDevice: observationsByDevice,
            classificationsByDevice: classificationsByDevice
        )
        let bestHeadphones = bestDevice(
            in: devices,
            category: .headphones,
            observationsByDevice: observationsByDevice,
            classificationsByDevice: classificationsByDevice
        )

        return [bestWatch, bestHeadphones]
            .compactMap { $0 }
            .sorted { $0.id < $1.id }
    }

    private func cappedOwnerDevices(
        from devices: [BluetoothDevice],
        snapshotsByDeviceId: [String: ClusterDetectionDeviceSnapshot],
        classificationsByDevice: [String: DetectedDeviceClassification]
    ) -> [BluetoothDevice] {
        let bestWatch = bestDevice(
            in: devices,
            category: .watch,
            snapshotsByDeviceId: snapshotsByDeviceId,
            classificationsByDevice: classificationsByDevice
        )
        let bestHeadphones = bestDevice(
            in: devices,
            category: .headphones,
            snapshotsByDeviceId: snapshotsByDeviceId,
            classificationsByDevice: classificationsByDevice
        )

        return [bestWatch, bestHeadphones]
            .compactMap { $0 }
            .sorted { $0.id < $1.id }
    }

    private func bestDevice(
        in devices: [BluetoothDevice],
        category: DeviceCategory,
        observationsByDevice: [String: [ScanObservation]],
        classificationsByDevice: [String: DetectedDeviceClassification]
    ) -> BluetoothDevice? {
        devices
            .filter { classificationsByDevice[$0.id]?.category == category }
            .max { lhs, rhs in
                let lhsRSSI = latestValidObservation(for: lhs.id, observationsByDevice: observationsByDevice)?.rssi ?? Int.min
                let rhsRSSI = latestValidObservation(for: rhs.id, observationsByDevice: observationsByDevice)?.rssi ?? Int.min
                return lhsRSSI < rhsRSSI
            }
    }

    private func bestDevice(
        in devices: [BluetoothDevice],
        category: DeviceCategory,
        snapshotsByDeviceId: [String: ClusterDetectionDeviceSnapshot],
        classificationsByDevice: [String: DetectedDeviceClassification]
    ) -> BluetoothDevice? {
        devices
            .filter { classificationsByDevice[$0.id]?.category == category }
            .max { lhs, rhs in
                let lhsRSSI = snapshotsByDeviceId[lhs.id]?.latestObservation.rssi ?? Int.min
                let rhsRSSI = snapshotsByDeviceId[rhs.id]?.latestObservation.rssi ?? Int.min
                return lhsRSSI < rhsRSSI
            }
    }

    private func smoothedCorrelation(for deviceId: String, anchorId: String, correlation: Double) -> Double {
        let key = pairKey(anchorId: anchorId, deviceId: deviceId)
        let previous = smoothedCorrelationByPairKey[key] ?? correlation
        let smoothed = (confidenceSmoothingAlpha * correlation) + ((1 - confidenceSmoothingAlpha) * previous)
        smoothedCorrelationByPairKey[key] = smoothed
        return smoothed
    }

    private func rssiBuckets(for observations: [ScanObservation], since cutoff: Date) -> [Int: Double] {
        let grouped = Dictionary(grouping: observations) { observation in
            Int(floor(observation.timestamp.timeIntervalSince1970))
        }

        return grouped.compactMapValues { observations in
            let validRSSI = observations
                .filter { $0.timestamp >= cutoff && $0.rssi >= rssiFloor }
                .map { Double($0.rssi) }

            guard !validRSSI.isEmpty else { return nil }
            return validRSSI.reduce(0, +) / Double(validRSSI.count)
        }
    }

    private func pearsonCorrelation(lhs: [Int: Double], rhs: [Int: Double]) -> Double {
        let overlappingKeys = Set(lhs.keys).intersection(rhs.keys).sorted()
        guard overlappingKeys.count >= minimumOverlapCount else { return 0 }

        let lhsValues = overlappingKeys.compactMap { lhs[$0] }
        let rhsValues = overlappingKeys.compactMap { rhs[$0] }
        let lhsMean = lhsValues.reduce(0, +) / Double(lhsValues.count)
        let rhsMean = rhsValues.reduce(0, +) / Double(rhsValues.count)

        let numerator = zip(lhsValues, rhsValues).reduce(0.0) { partial, values in
            partial + ((values.0 - lhsMean) * (values.1 - rhsMean))
        }
        let lhsVariance = lhsValues.reduce(0.0) { $0 + pow($1 - lhsMean, 2) }
        let rhsVariance = rhsValues.reduce(0.0) { $0 + pow($1 - rhsMean, 2) }

        guard lhsVariance > 0, rhsVariance > 0 else { return 0 }
        return numerator / sqrt(lhsVariance * rhsVariance)
    }

    private func pairwiseCorrelations(
        deviceIds: [String],
        bucketsByDeviceId: [String: [Int: Double]]
    ) -> [Double] {
        guard deviceIds.count >= 2 else { return [] }

        var correlations: [Double] = []
        for leftIndex in deviceIds.indices {
            for rightIndex in deviceIds.indices where rightIndex > leftIndex {
                correlations.append(
                    pearsonCorrelation(
                        lhs: bucketsByDeviceId[deviceIds[leftIndex]] ?? [:],
                        rhs: bucketsByDeviceId[deviceIds[rightIndex]] ?? [:]
                    )
                )
            }
        }
        return correlations
    }

    private func isStationaryDevice(
        deviceId: String,
        observationsByDevice: [String: [ScanObservation]],
        at date: Date
    ) -> Bool {
        let values = (observationsByDevice[deviceId] ?? [])
            .filter { $0.timestamp >= date.addingTimeInterval(-rollingHistoryWindow) && $0.rssi >= rssiFloor }
            .map { Double($0.rssi) }

        guard values.count >= minimumOverlapCount else { return false }
        return variance(values) < stationaryVarianceThreshold
    }

    private func variance(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        return values.reduce(0.0) { $0 + pow($1 - mean, 2) } / Double(values.count)
    }

    private func medianRSSI(for observations: [ScanObservation], since cutoff: Date) -> Double? {
        let values = observations
            .filter { $0.timestamp >= cutoff && $0.rssi >= rssiFloor }
            .map(\.rssi)
            .sorted()

        guard !values.isEmpty else { return nil }
        let middle = values.count / 2
        if values.count.isMultiple(of: 2) {
            return Double(values[middle - 1] + values[middle]) / 2
        } else {
            return Double(values[middle])
        }
    }

    private func latestValidObservation(
        for deviceId: String,
        observationsByDevice: [String: [ScanObservation]]
    ) -> ScanObservation? {
        observationsByDevice[deviceId]?
            .filter { $0.rssi >= rssiFloor }
            .max { $0.timestamp < $1.timestamp }
    }

    private func personalDeviceWeight(for category: DeviceCategory?) -> Double? {
        switch category {
        case .watch:
            return 0.35
        case .headphones:
            return 0.3
        case .phone, .wearable, .health, .tracker, .computer, .keyboard, .mouse, .vehicle, .tv, .lighting, .unknown, nil:
            return nil
        }
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

    private func reasons(for isPhoneOnly: Bool, isOwnerGroup: Bool, memberCount: Int = 0) -> [String] {
        if isOwnerGroup {
            if memberCount == 1 {
                return [
                    "A nearby personal device is close to the scanning iPhone without a visible phone advertisement.",
                    "This is treated as a low-confidence owner group because the scanning iPhone does not advertise itself."
                ]
            }

            return [
                "Nearby personal devices move together without a visible phone advertisement.",
                "This is treated as the owner's group because the scanning iPhone does not advertise itself."
            ]
        }

        if isPhoneOnly {
            return [
                "This phone is currently visible.",
                "No strongly correlated personal devices are stable enough to join it yet."
            ]
        }

        return [
            "These devices have strongly correlated RSSI movement.",
            "The group is anchored by a visible phone.",
            "Confidence is smoothed over time as devices continue moving together."
        ]
    }

    private func clusterSort(_ lhs: DeviceCluster, _ rhs: DeviceCluster) -> Bool {
        if lhs.confidenceScore != rhs.confidenceScore {
            return lhs.confidenceScore > rhs.confidenceScore
        }

        if lhs.isOwnerGroup != rhs.isOwnerGroup {
            return !lhs.isOwnerGroup
        }

        return lhs.lastSeen > rhs.lastSeen
    }

    private func pairKey(anchorId: String, deviceId: String) -> String {
        "\(anchorId)|\(deviceId)"
    }

    private func stableClusterId(key: String) -> UUID {
        let digest = SHA256.hash(data: Data(key.utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80

        return bytes.withUnsafeBufferPointer { buffer in
            UUID(uuidString: NSUUID(uuidBytes: buffer.baseAddress!).uuidString) ?? UUID()
        }
    }
}

private extension DetectedDeviceClassification {
    static func placeholder(category: DeviceCategory) -> DetectedDeviceClassification {
        DetectedDeviceClassification(
            manufacturer: nil,
            appearance: nil,
            category: category,
            likelyProduct: nil,
            confidence: 0,
            evidence: []
        )
    }
}
