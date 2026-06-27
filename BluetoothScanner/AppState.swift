import Foundation
import Combine

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
    private let clusterService = ClusterDetectionService()
    private var cancellables: Set<AnyCancellable> = []
    private var pendingSaveTask: Task<Void, Never>?
    private var pendingClusterRebuildTask: Task<Void, Never>?
    private var pendingLiveOverviewTask: Task<Void, Never>?
    private var distanceEstimators: [String: BLEDistanceEstimator] = [:]
    private var lastDistanceSnapshots: [String: BLEDistanceSnapshot] = [:]
    private var proximityStabilizers: [String: ProximityStabilizer] = [:]
    private var deviceIndex: [String: Int] = [:]  // deviceId → index in devices array
    private var observationsByDevice: [String: [ScanObservation]] = [:]
    private var latestObservationByDevice: [String: ScanObservation] = [:]
    private var classificationByDevice: [String: DetectedDeviceClassification] = [:]
    private var trackedDeviceIds: Set<String> = [] // devices whose detail view is currently open
    private let maximumStoredObservations = 5_000

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

        scanner.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
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
            rebuildClusters()
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
            self?.rebuildClusters()
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
        latestObservationByDevice = [:]
        classificationByDevice = [:]
        trackedDeviceIds = []
        sessionService.reset()
        clusterService.reset()

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
            observations: observationsByDevice[device.id] ?? []
        )
        classificationByDevice[device.id] = classification
        return classification
    }

    private func classification(for device: BluetoothDevice, observations deviceObservations: [ScanObservation]) -> DetectedDeviceClassification {
        let latestObservations = deviceObservations
        let latestManufacturerIdentifier = latestObservations.lazy.compactMap(\.manufacturerIdentifier).first
        let latestAppearanceValue = latestObservations.lazy.compactMap(\.appearanceValue).first
        let snapshot = BluetoothAdvertisementSnapshot(
            localName: preferredLocalName(for: device),
            manufacturerCompanyId: manufacturerCompanyId(from: latestManufacturerIdentifier),
            appearanceId: latestAppearanceValue,
            serviceUUIDs: deviceObservations.flatMap(\.serviceUUIDs)
        )

        return deviceClassifier.classify(snapshot)
    }

    private func record(observation: ScanObservation, device incomingDevice: BluetoothDevice) async {
        let device = merge(device: incomingDevice)
        updateDistanceCache(for: device.id, rssi: observation.rssi, at: observation.timestamp)
        proximityStabilizer(for: device.id).update(rssi: observation.rssi, at: observation.timestamp)

        observations.append(observation)
        appendObservationIndex(observation)
        classificationByDevice[device.id] = nil
        trimStoredObservationsIfNeeded()
        sessionService.record(deviceId: device.id, at: observation.timestamp)
        sessions = sessionService.sessions
        scheduleLiveOverviewRebuild()
        scheduleClusterRebuild()
        scheduleSave()
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

    private func rebuildClusters() {
        let currentClassifications = Dictionary(
            uniqueKeysWithValues: devices.map { device in
                (device.id, classification(for: device))
            }
        )
        let result = clusterService.detectClusters(
            devices: devices,
            observationsByDevice: observationsByDevice,
            classificationsByDevice: currentClassifications
        )
        clusters = result.clusters
    }

    private func rebuildDeviceIndex() {
        deviceIndex = Dictionary(
            uniqueKeysWithValues: devices.enumerated().map { ($0.element.id, $0.offset) }
        )
    }

    private func rebuildObservationIndexes() {
        observationsByDevice = Dictionary(grouping: observations, by: \.deviceId)
            .mapValues { observations in
                observations.sorted { $0.timestamp > $1.timestamp }
            }

        latestObservationByDevice = observationsByDevice.compactMapValues(\.first)
    }

    private func appendObservationIndex(_ observation: ScanObservation) {
        var deviceObservations = observationsByDevice[observation.deviceId] ?? []
        deviceObservations.insert(observation, at: 0)
        observationsByDevice[observation.deviceId] = deviceObservations
        latestObservationByDevice[observation.deviceId] = observation
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
            self?.rebuildClusters()
        }
    }

    private func trimStoredObservationsIfNeeded() {
        guard observations.count > maximumStoredObservations else { return }
        observations.removeFirst(observations.count - maximumStoredObservations)
        rebuildObservationIndexes()
        classificationByDevice = [:]
    }

    private func rebuildLiveOverview() {
        let visibleDevices = devices.sorted { $0.lastSeen > $1.lastSeen }

        guard !visibleDevices.isEmpty else {
            knownDeviceCategorySummaries = []
            knownDeviceManufacturerSummaries = []
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

        knownDeviceCategorySummaries = devicesByKnownCategory
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

        knownDeviceManufacturerSummaries = devicesByKnownManufacturer
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
            try await storage.save(
                AppDataSnapshot(
                    devices: devices,
                    observations: observations,
                    sessions: sessions
                )
            )
            lastStorageError = nil
        } catch {
            lastStorageError = error.localizedDescription
        }
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
