import Foundation
import OSLog

private struct ClassificationInputKey: Equatable, Sendable {
    var localName: String?
    var manufacturerIdentifier: String?
    var appearanceValue: Int?
    var serviceUUIDs: [String]
}

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var devices: [BluetoothDevice] = []
    @Published private(set) var observations: [ScanObservation] = []
    @Published private(set) var sessions: [ScanSession] = []
    @Published private(set) var clusters: [DeviceCluster] = []
    @Published private(set) var knownDeviceCategorySummaries: [KnownDeviceCategorySummary] = []
    @Published private(set) var knownDeviceManufacturerSummaries: [KnownDeviceManufacturerSummary] = []
    @Published var lastStorageError: String?

    let scanner = BluetoothScannerService()

    private let storage = LocalStorageService()
    private lazy var deviceClassifier: DeviceClassifier = {
        let manufacturerLookup = ManufacturerLookup()
        let appearanceLookup = AppearanceLookup()
        return DeviceClassifier(
            manufacturerLookup: manufacturerLookup,
            appearanceLookup: appearanceLookup
        )
    }()
    private var sessionService = SessionService()
    private let clusterWorker = ClusterDetectionWorker()
    private let logger = Logger(subsystem: "BluetoothScanner", category: "AppState")
    private var pendingSaveTask: Task<Void, Never>?
    private var pendingClusterRebuildTask: Task<Void, Never>?
    private var pendingLiveOverviewTask: Task<Void, Never>?
    private var distanceEstimators: [String: BLEDistanceEstimator] = [:]
    private var lastDistanceSnapshots: [String: BLEDistanceSnapshot] = [:]
    private var proximityStabilizers: [String: ProximityStabilizer] = [:]
    private var deviceIndex: [String: Int] = [:]  // deviceId → index in devices array
    private var observationsByDevice: [String: [ScanObservation]] = [:]
    private var recentObservationsByDevice: [String: [ScanObservation]] = [:]
    private var latestObservationByDevice: [String: ScanObservation] = [:]
    private var classificationByDevice: [String: DetectedDeviceClassification] = [:]
    private var classificationInputByDevice: [String: ClassificationInputKey] = [:]
    private var trackedDeviceIds: Set<String> = [] // devices whose detail view is currently open
    private let maximumStoredObservations = 5_000
    private let clusterRollingHistoryWindow: TimeInterval = 30
    private let clusterCorrelationWindow: TimeInterval = 20
    private let clusterMinimumOverlapCount = 5
    private let clusterStationaryVarianceThreshold = 2.0
    private let clusterRSSIFloor = -100

    // Activity-status thresholds (seconds). A device seen within the online
    // threshold is "Online"; seen within the recently-seen threshold but
    // outside the online window is "Recently Seen"; everything else is "Offline".
    private let activityStatusOnlineThreshold: TimeInterval = 8
    private let activityStatusRecentlySeenThreshold: TimeInterval = 30

    init() {
        scanner.onObservation = { [weak self] observation, device in
            Task { @MainActor in
                await self?.record(observation: observation, device: device)
            }
        }
    }

    func load() async {
        do {
            let snapshot = try await storage.load()
            devices = snapshot.devices
            observations = snapshot.observations
            sessions = snapshot.sessions
            sessionService.restore(sessions: snapshot.sessions)
            rebuildDeviceIndex()
            rebuildObservationIndexes()
            classificationByDevice = [:]
            rebuildClassificationInputs()
            await rebuildClusters()
            rebuildLiveOverview()
        } catch {
            lastStorageError = error.localizedDescription
        }
    }

    func startScan() {
        sessionService.startSession()
        scanner.startScanning()
    }

    func stopScan() {
        scanner.stopScanning()
        sessions = sessionService.endCurrentSession()
        pendingClusterRebuildTask?.cancel()
        pendingClusterRebuildTask = nil
        pendingSaveTask?.cancel()
        Task { @MainActor [weak self] in
            await self?.rebuildClusters()
            self?.rebuildLiveOverview()
            await self?.save()
        }
    }

    func clearScanData() {
        scanner.clearLiveData()
        pendingClusterRebuildTask?.cancel()
        pendingClusterRebuildTask = nil
        pendingLiveOverviewTask?.cancel()
        pendingSaveTask?.cancel()
        devices = []
        observations = []
        sessions = []
        clusters = []
        knownDeviceCategorySummaries = []
        knownDeviceManufacturerSummaries = []
        distanceEstimators = [:]
        lastDistanceSnapshots = [:]
        proximityStabilizers = [:]
        deviceIndex = [:]
        observationsByDevice = [:]
        recentObservationsByDevice = [:]
        latestObservationByDevice = [:]
        classificationByDevice = [:]
        classificationInputByDevice = [:]
        trackedDeviceIds = []
        sessionService.reset()
        Task {
            await clusterWorker.reset()
        }

        Task {
            await save()
        }
    }

    func device(id: String) -> BluetoothDevice? {
        if let index = deviceIndex[id] {
            return devices[index]
        }
        return scanner.liveDevices.first { $0.id == id }
    }

    func observations(for deviceId: String) -> [ScanObservation] {
        observationsByDevice[deviceId] ?? []
    }

    func latestObservation(for deviceId: String) -> ScanObservation? {
        latestObservationByDevice[deviceId]
    }

    func liveRSSI(for deviceId: String) -> Int? {
        scanner.liveRSSI[deviceId]
    }

    func distanceCategory(for deviceId: String) -> DistanceCategory {
        DistanceCategory(rssi: liveRSSI(for: deviceId) ?? latestObservationByDevice[deviceId]?.rssi)
    }

    func distanceSnapshot(for deviceId: String, at date: Date = Date()) -> BLEDistanceSnapshot {
        seedDistanceEstimatorIfNeeded(for: deviceId)

        let snapshot = estimator(for: deviceId).snapshot(at: date)
        if snapshot.isAvailable {
            lastDistanceSnapshots[deviceId] = snapshot
            return snapshot
        }

        if !scanner.isScanning, let cachedSnapshot = lastDistanceSnapshots[deviceId] {
            return cachedSnapshot
        }

        return snapshot
    }

    func activityStatus(for deviceId: String, at date: Date = Date()) -> ActivityStatus {
        guard let device = device(id: deviceId) else { return .offline }
        let elapsed = date.timeIntervalSince(device.lastSeen)

        if elapsed <= activityStatusOnlineThreshold {
            return .online
        } else if elapsed <= activityStatusRecentlySeenThreshold {
            return .recentlySeen
        } else {
            return .offline
        }
    }

    /// Begins active distance tracking for a device (called when its detail view appears).
    /// Seeds the estimator with the latest live RSSI so the UI has data immediately.
    func startTrackingDistance(for deviceId: String) {
        trackedDeviceIds.insert(deviceId)
        if let rssi = scanner.liveRSSI[deviceId] {
            estimator(for: deviceId).update(rssi: rssi)
            proximityStabilizer(for: deviceId).update(rssi: rssi)
        }
    }

    /// Stops active distance tracking for a device (called when its detail view disappears).
    /// The estimators and their cached snapshots are preserved so re-opening the detail view
    /// continues from the last-known state.
    func stopTrackingDistance(for deviceId: String) {
        trackedDeviceIds.remove(deviceId)
    }

    /// Returns the stabilised proximity state for a device.
    ///
    /// The state is computed from a rolling median of the last 7 RSSI readings,
    /// passed through hysteresis, persistence filtering, and 2-second debouncing.
    /// See `ProximityStabilizer` for the full pipeline.
    func stabilizedProximity(for deviceId: String, at date: Date = Date()) -> ProximityState {
        proximityStabilizer(for: deviceId).currentProximity(at: date)
    }

    func devices(in category: DeviceCategory) -> [BluetoothDevice] {
        return devices
            .filter { device in
                let classification = classification(for: device)
                return classification.category == category && shouldAppearInCategoryOverview(classification)
            }
            .sortedByDeviceIdentifier()
    }

    func devices(inKnownCategory categoryName: String) -> [BluetoothDevice] {
        return devices
            .filter { device in
                let classification = classification(for: device)
                return classification.categoryName == categoryName && shouldAppearInCategoryOverview(classification)
            }
            .sortedByDeviceIdentifier()
    }

    func devices(forKnownManufacturer manufacturerName: String) -> [BluetoothDevice] {
        return devices
            .filter { device in
                let classification = classification(for: device)
                return manufacturerDisplayName(for: classification) == manufacturerName
            }
            .sortedByDeviceIdentifier()
    }

    func classification(for device: BluetoothDevice) -> DetectedDeviceClassification {
        if let classification = classificationByDevice[device.id] {
            return classification
        }

        let classification = classification(
            for: device,
            input: classificationInput(for: device)
        )
        classificationByDevice[device.id] = classification
        return classification
    }

    private func classification(for device: BluetoothDevice, input: ClassificationInputKey) -> DetectedDeviceClassification {
        let snapshot = BluetoothAdvertisementSnapshot(
            localName: input.localName,
            manufacturerCompanyId: manufacturerCompanyId(from: input.manufacturerIdentifier),
            appearanceId: input.appearanceValue,
            serviceUUIDs: input.serviceUUIDs
        )

        return deviceClassifier.classify(snapshot)
    }

    private func record(observation: ScanObservation, device incomingDevice: BluetoothDevice) async {
        let startedAt = Date()
        let device = merge(device: incomingDevice)
        updateDistanceCache(for: device.id, rssi: observation.rssi, at: observation.timestamp)
        proximityStabilizer(for: device.id).update(rssi: observation.rssi, at: observation.timestamp)

        observations.append(observation)
        appendObservationIndex(observation)
        updateClassificationInput(for: device, observation: observation)
        trimStoredObservationsIfNeeded()
        sessionService.record(deviceId: device.id, at: observation.timestamp)
        assignIfChanged(&sessions, sessionService.sessions)
        scheduleLiveOverviewRebuild()
        scheduleClusterRebuild()
        scheduleSave()
        logDuration("record", since: startedAt)
    }

    @discardableResult
    private func merge(device incomingDevice: BluetoothDevice) -> BluetoothDevice {
        if let index = deviceIndex[incomingDevice.id] {
            devices[index].displayName = incomingDevice.displayName ?? devices[index].displayName
            devices[index].advertisedName = incomingDevice.advertisedName ?? devices[index].advertisedName
            devices[index].lastSeen = max(devices[index].lastSeen, incomingDevice.lastSeen)
            return devices[index]
        } else {
            devices.append(incomingDevice)
            deviceIndex[incomingDevice.id] = devices.count - 1
            return incomingDevice
        }
    }

    private func rebuildClusters() async {
        let startedAt = Date()
        let snapshots = clusterSnapshots(at: startedAt)
        let result = await clusterWorker.detectClusters(
            snapshots: snapshots,
            at: startedAt
        )
        assignIfChanged(&clusters, result.clusters)
        logDuration("rebuildClusters", since: startedAt)
    }

    private func rebuildDeviceIndex() {
        deviceIndex = Dictionary(
            uniqueKeysWithValues: devices.enumerated().map { ($0.element.id, $0.offset) }
        )
    }

    private func rebuildObservationIndexes() {
        observationsByDevice = Dictionary(grouping: observations, by: \.deviceId)
            .mapValues { observations in
                observations.sorted { $0.timestamp < $1.timestamp }
            }

        latestObservationByDevice = observationsByDevice.compactMapValues(\.last)
        rebuildRecentObservationIndexes(at: Date())
    }

    private func appendObservationIndex(_ observation: ScanObservation) {
        observationsByDevice[observation.deviceId, default: []].append(observation)
        recentObservationsByDevice[observation.deviceId, default: []].append(observation)
        trimRecentObservations(for: observation.deviceId, at: observation.timestamp)

        if let latest = latestObservationByDevice[observation.deviceId] {
            if observation.timestamp >= latest.timestamp {
                latestObservationByDevice[observation.deviceId] = observation
            }
        } else {
            latestObservationByDevice[observation.deviceId] = observation
        }
    }

    private func estimator(for deviceId: String) -> BLEDistanceEstimator {
        if let estimator = distanceEstimators[deviceId] {
            return estimator
        }

        let estimator = BLEDistanceEstimator()
        distanceEstimators[deviceId] = estimator
        return estimator
    }

    private func proximityStabilizer(for deviceId: String) -> ProximityStabilizer {
        if let stabilizer = proximityStabilizers[deviceId] {
            return stabilizer
        }

        let stabilizer = ProximityStabilizer()
        proximityStabilizers[deviceId] = stabilizer
        return stabilizer
    }

    private func seedDistanceEstimatorIfNeeded(for deviceId: String) {
        guard lastDistanceSnapshots[deviceId] == nil,
              let latestObservation = latestObservationByDevice[deviceId]
        else { return }

        updateDistanceCache(
            for: deviceId,
            rssi: latestObservation.rssi,
            at: latestObservation.timestamp
        )
    }

    private func updateDistanceCache(for deviceId: String, rssi: Int, at date: Date) {
        let estimator = estimator(for: deviceId)
        estimator.update(rssi: rssi, at: date)
        let snapshot = estimator.snapshot(at: date)
        if snapshot.isAvailable {
            lastDistanceSnapshots[deviceId] = snapshot
        }
    }

    private func scheduleLiveOverviewRebuild() {
        pendingLiveOverviewTask?.cancel()
        pendingLiveOverviewTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(0.5))
            guard !Task.isCancelled else { return }
            self?.rebuildLiveOverview()
        }
    }

    private func scheduleClusterRebuild() {
        guard pendingClusterRebuildTask == nil else { return }

        pendingClusterRebuildTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.pendingClusterRebuildTask = nil
            await self?.rebuildClusters()
        }
    }

    private func trimStoredObservationsIfNeeded() {
        guard observations.count > maximumStoredObservations else { return }
        observations.removeFirst(observations.count - maximumStoredObservations)
        rebuildObservationIndexes()
        classificationByDevice = [:]
        rebuildClassificationInputs()
    }

    private func rebuildLiveOverview() {
        let startedAt = Date()
        let visibleDevices = devices.sorted { $0.lastSeen > $1.lastSeen }

        guard !visibleDevices.isEmpty else {
            assignIfChanged(&knownDeviceCategorySummaries, [])
            assignIfChanged(&knownDeviceManufacturerSummaries, [])
            logDuration("rebuildLiveOverview", since: startedAt)
            return
        }
        let classifiedDevices = visibleDevices.map { device in
            (
                device: device,
                classification: classification(for: device)
            )
        }

        let categoryVisibleDevices = classifiedDevices.filter { item in
            shouldAppearInCategoryOverview(item.classification)
        }

        let devicesByKnownCategory = Dictionary(grouping: categoryVisibleDevices) { item in
            item.classification.categoryName
        }

        let categorySummaries = devicesByKnownCategory
            .map { categoryName, items in
                KnownDeviceCategorySummary(
                    categoryName: categoryName,
                    symbolName: items.first?.classification.symbolName ?? "sensor.tag.radiowaves.forward",
                    count: items.count,
                    lastSeen: items.map(\.device.lastSeen).max()
                )
            }
            .sorted {
                // Always push unavailable categories to the bottom.
                if $0.categoryName == "-" { return false }
                if $1.categoryName == "-" { return true }
                if $0.count == $1.count {
                    return $0.categoryName < $1.categoryName
                }
                return $0.count > $1.count
            }

        let devicesByKnownManufacturer = Dictionary(grouping: classifiedDevices) { item in
            manufacturerDisplayName(for: item.classification)
        }

        let manufacturerSummaries = devicesByKnownManufacturer
            .map { manufacturerName, items in
                KnownDeviceManufacturerSummary(
                    manufacturerName: manufacturerName,
                    count: items.count
                )
            }
            .sorted {
                if $0.manufacturerName == "-" { return false }
                if $1.manufacturerName == "-" { return true }
                if $0.count == $1.count {
                    return $0.manufacturerName < $1.manufacturerName
                }
                return $0.count > $1.count
            }
        assignIfChanged(&knownDeviceCategorySummaries, categorySummaries)
        assignIfChanged(&knownDeviceManufacturerSummaries, manufacturerSummaries)
        logDuration("rebuildLiveOverview", since: startedAt)
    }

    private func manufacturerDisplayName(for classification: DetectedDeviceClassification) -> String {
        classification.manufacturerName ?? "-"
    }

    private func shouldAppearInCategoryOverview(_ classification: DetectedDeviceClassification) -> Bool {
        classification.category != .unknown || classification.manufacturerName == nil
    }

    private func preferredLocalName(for device: BluetoothDevice) -> String? {
        if let localAlias = device.localAlias, !localAlias.isEmpty {
            return localAlias
        }

        if let advertisedName = device.advertisedName, !advertisedName.isEmpty {
            return advertisedName
        }

        if let displayName = device.displayName, displayName != "Unknown BLE Device", displayName != "-" {
            return displayName
        }

        return nil
    }

    private func manufacturerCompanyId(from identifier: String?) -> Int? {
        guard let identifier else { return nil }
        let normalized = identifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "0X", with: "")

        return Int(normalized, radix: 16) ?? Int(normalized)
    }

    private func scheduleSave() {
        pendingSaveTask?.cancel()
        pendingSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.save()
        }
    }

    private func save() async {
        do {
            let startedAt = Date()
            let snapshot = AppDataSnapshot(
                devices: devices,
                observations: observations,
                sessions: sessions
            )
            logDuration("save snapshot", since: startedAt)
            try await storage.save(snapshot)
            lastStorageError = nil
        } catch {
            lastStorageError = error.localizedDescription
        }
    }

    private func classificationInput(for device: BluetoothDevice) -> ClassificationInputKey {
        if let input = classificationInputByDevice[device.id] {
            return input
        }

        let input = makeClassificationInput(
            for: device,
            observations: observationsByDevice[device.id] ?? []
        )
        classificationInputByDevice[device.id] = input
        return input
    }

    private func updateClassificationInput(for device: BluetoothDevice, observation: ScanObservation) {
        let existing = classificationInputByDevice[device.id]
            ?? makeClassificationInput(for: device, observations: observationsByDevice[device.id] ?? [])
        var serviceUUIDs = Set(existing.serviceUUIDs)
        serviceUUIDs.formUnion(observation.serviceUUIDs)

        let updated = ClassificationInputKey(
            localName: preferredLocalName(for: device),
            manufacturerIdentifier: observation.manufacturerIdentifier ?? existing.manufacturerIdentifier,
            appearanceValue: observation.appearanceValue ?? existing.appearanceValue,
            serviceUUIDs: serviceUUIDs.sorted()
        )

        if updated != existing {
            classificationByDevice[device.id] = nil
            classificationInputByDevice[device.id] = updated
        } else if classificationInputByDevice[device.id] == nil {
            classificationInputByDevice[device.id] = updated
        }
    }

    private func rebuildClassificationInputs() {
        classificationInputByDevice = Dictionary(
            uniqueKeysWithValues: devices.map { device in
                (
                    device.id,
                    makeClassificationInput(
                        for: device,
                        observations: observationsByDevice[device.id] ?? []
                    )
                )
            }
        )
    }

    private func makeClassificationInput(
        for device: BluetoothDevice,
        observations deviceObservations: [ScanObservation]
    ) -> ClassificationInputKey {
        let latestManufacturerIdentifier = deviceObservations.reversed().lazy.compactMap(\.manufacturerIdentifier).first
        let latestAppearanceValue = deviceObservations.reversed().lazy.compactMap(\.appearanceValue).first
        let serviceUUIDs = Set(deviceObservations.flatMap(\.serviceUUIDs)).sorted()

        return ClassificationInputKey(
            localName: preferredLocalName(for: device),
            manufacturerIdentifier: latestManufacturerIdentifier,
            appearanceValue: latestAppearanceValue,
            serviceUUIDs: serviceUUIDs
        )
    }

    private func rebuildRecentObservationIndexes(at date: Date) {
        let cutoff = date.addingTimeInterval(-clusterRollingHistoryWindow)
        recentObservationsByDevice = observationsByDevice.mapValues { observations in
            observations.filter { $0.timestamp >= cutoff }
        }
    }

    private func trimRecentObservations(for deviceId: String, at date: Date) {
        let cutoff = date.addingTimeInterval(-clusterRollingHistoryWindow)
        recentObservationsByDevice[deviceId]?.removeAll { $0.timestamp < cutoff }
    }

    private func clusterSnapshots(at date: Date) -> [ClusterDetectionDeviceSnapshot] {
        devices.compactMap { device in
            guard let latestObservation = latestObservationByDevice[device.id],
                  latestObservation.rssi >= clusterRSSIFloor
            else { return nil }

            let recentObservations = recentObservationsByDevice[device.id] ?? []
            let rollingRSSIValues = recentObservations
                .filter { $0.timestamp >= date.addingTimeInterval(-clusterRollingHistoryWindow) && $0.rssi >= clusterRSSIFloor }
                .map { Double($0.rssi) }

            return ClusterDetectionDeviceSnapshot(
                device: device,
                category: classification(for: device).category,
                latestObservation: latestObservation,
                firstSeen: device.firstSeen,
                correlationBuckets: rssiBuckets(
                    for: recentObservations,
                    since: date.addingTimeInterval(-clusterCorrelationWindow)
                ),
                rollingBuckets: rssiBuckets(
                    for: recentObservations,
                    since: date.addingTimeInterval(-clusterRollingHistoryWindow)
                ),
                isStationary: isStationaryRSSI(rollingRSSIValues),
                medianRSSI: median(rollingRSSIValues)
            )
        }
    }

    private func rssiBuckets(for observations: [ScanObservation], since cutoff: Date) -> [Int: Double] {
        let grouped = Dictionary(grouping: observations) { observation in
            Int(floor(observation.timestamp.timeIntervalSince1970))
        }

        return grouped.compactMapValues { observations in
            let validRSSI = observations
                .filter { $0.timestamp >= cutoff && $0.rssi >= clusterRSSIFloor }
                .map { Double($0.rssi) }

            guard !validRSSI.isEmpty else { return nil }
            return validRSSI.reduce(0, +) / Double(validRSSI.count)
        }
    }

    private func isStationaryRSSI(_ values: [Double]) -> Bool {
        guard values.count >= clusterMinimumOverlapCount else { return false }
        return variance(values) < clusterStationaryVarianceThreshold
    }

    private func variance(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        return values.reduce(0.0) { $0 + pow($1 - mean, 2) } / Double(values.count)
    }

    private func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sortedValues = values.sorted()
        let middle = sortedValues.count / 2
        if sortedValues.count.isMultiple(of: 2) {
            return (sortedValues[middle - 1] + sortedValues[middle]) / 2
        } else {
            return sortedValues[middle]
        }
    }

    private func assignIfChanged<Value: Equatable>(_ value: inout Value, _ newValue: Value) {
        if value != newValue {
            value = newValue
        }
    }

    private func logDuration(_ operation: StaticString, since startedAt: Date) {
        let elapsedMilliseconds = Date().timeIntervalSince(startedAt) * 1_000
        logger.debug("\(operation, privacy: .public) completed in \(elapsedMilliseconds, format: .fixed(precision: 2), privacy: .public) ms")
    }

}

#if DEBUG
extension AppState {
    static var preview: AppState {
        let state = AppState()
        state.loadPreviewData()
        return state
    }

    private func loadPreviewData() {
        devices = PreviewData.devices
        observations = PreviewData.observations
        sessions = PreviewData.sessions
        clusters = PreviewData.clusters
        rebuildDeviceIndex()
        rebuildObservationIndexes()
        classificationByDevice = [:]
        rebuildLiveOverview()

        for observation in observations {
            updateDistanceCache(
                for: observation.deviceId,
                rssi: observation.rssi,
                at: observation.timestamp
            )
            proximityStabilizer(for: observation.deviceId).update(
                rssi: observation.rssi,
                at: observation.timestamp
            )
        }
    }
}
#endif

private extension Array where Element == BluetoothDevice {
    func sortedByDeviceIdentifier() -> [BluetoothDevice] {
        sorted {
            let lhs = $0.id.replacingOccurrences(of: "-", with: "").uppercased()
            let rhs = $1.id.replacingOccurrences(of: "-", with: "").uppercased()

            if lhs == rhs {
                return ($0.displayName ?? "") < ($1.displayName ?? "")
            }

            return lhs < rhs
        }
    }
}
