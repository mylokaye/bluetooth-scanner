import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var devices: [BluetoothDevice] = []
    @Published private(set) var observations: [ScanObservation] = []
    @Published private(set) var sessions: [ScanSession] = []
    @Published private(set) var clusters: [DeviceCluster] = []
    @Published private(set) var knownDeviceCategorySummaries: [KnownDeviceCategorySummary] = []
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
    private var deviceIndex: [String: Int] = [:]  // deviceId → index in devices array
    private var trackedDeviceIds: Set<String> = [] // devices whose detail view is currently open
    private let maximumStoredObservations = 5_000

    // Activity-status thresholds (seconds). A device seen within the online
    // threshold is "Online"; seen within the recently-seen threshold but
    // outside the online window is "Recently Seen"; everything else is "Offline".
    private let activityStatusOnlineThreshold: TimeInterval = 15
    private let activityStatusRecentlySeenThreshold: TimeInterval = 300

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
        rebuildClusters()
        rebuildLiveOverview()
        pendingSaveTask?.cancel()
        Task {
            await save()
        }
    }

    func clearScanData() {
        scanner.clearLiveData()
        pendingClusterRebuildTask?.cancel()
        pendingLiveOverviewTask?.cancel()
        pendingSaveTask?.cancel()
        devices = []
        observations = []
        sessions = []
        clusters = []
        knownDeviceCategorySummaries = []
        distanceEstimators = [:]
        deviceIndex = [:]
        trackedDeviceIds = []
        sessionService.reset()

        Task {
            await save()
        }
    }

    func ignore(device: BluetoothDevice) {
        guard let index = deviceIndex[device.id] else { return }
        devices[index].isIgnored = true
        scanner.ignoreDevice(id: device.id)
        distanceEstimators[device.id] = nil
        pendingClusterRebuildTask?.cancel()
        rebuildClusters()
        rebuildLiveOverview()
        scheduleSave()
    }

    func device(id: String) -> BluetoothDevice? {
        if let index = deviceIndex[id] {
            return devices[index]
        }
        return scanner.liveDevices.first { $0.id == id }
    }

    func observations(for deviceId: String) -> [ScanObservation] {
        observations
            .filter { $0.deviceId == deviceId }
            .sorted { $0.timestamp > $1.timestamp }
    }

    func liveRSSI(for deviceId: String) -> Int? {
        scanner.liveRSSI[deviceId]
    }

    func distanceCategory(for deviceId: String) -> DistanceCategory {
        DistanceCategory(rssi: liveRSSI(for: deviceId) ?? observations(for: deviceId).first?.rssi)
    }

    func distanceSnapshot(for deviceId: String, at date: Date = Date()) -> BLEDistanceSnapshot {
        estimator(for: deviceId).snapshot(at: date)
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
        }
    }

    /// Stops active distance tracking for a device (called when its detail view disappears).
    /// The estimator and its cached snapshot are preserved so re-opening the detail view
    /// continues from the last-known state.
    func stopTrackingDistance(for deviceId: String) {
        trackedDeviceIds.remove(deviceId)
    }

    func devices(in category: DeviceCategory) -> [BluetoothDevice] {
        let observationsByDevice = Dictionary(grouping: observations, by: \.deviceId)

        return devices
            .filter { !$0.isIgnored }
            .filter { device in
                classification(for: device, observations: observationsByDevice[device.id] ?? []).category == category
            }
            .sorted { $0.lastSeen > $1.lastSeen }
    }

    func devices(inKnownCategory categoryName: String) -> [BluetoothDevice] {
        let observationsByDevice = Dictionary(grouping: observations, by: \.deviceId)

        return devices
            .filter { !$0.isIgnored }
            .filter { device in
                classification(
                    for: device,
                    observations: observationsByDevice[device.id] ?? []
                ).categoryName == categoryName
            }
            .sorted { $0.lastSeen > $1.lastSeen }
    }

    func classification(for device: BluetoothDevice) -> DetectedDeviceClassification {
        let deviceObservations = observations(for: device.id)
        return classification(for: device, observations: deviceObservations)
    }

    private func classification(for device: BluetoothDevice, observations deviceObservations: [ScanObservation]) -> DetectedDeviceClassification {
        let latestObservations = deviceObservations.sorted { $0.timestamp > $1.timestamp }
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

        // Only update the distance estimator when the device detail view is
        // currently open — avoids wasted computation for off-screen devices.
        if trackedDeviceIds.contains(device.id) {
            estimator(for: device.id).update(rssi: observation.rssi, at: observation.timestamp)
        }

        observations.append(observation)
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
        clusters = clusterService.detectClusters(
            devices: devices,
            observations: observations,
            sessions: sessions
        )
    }

    private func rebuildDeviceIndex() {
        deviceIndex = Dictionary(
            uniqueKeysWithValues: devices.enumerated().map { ($0.element.id, $0.offset) }
        )
    }

    private func estimator(for deviceId: String) -> BLEDistanceEstimator {
        if let estimator = distanceEstimators[deviceId] {
            return estimator
        }

        let estimator = BLEDistanceEstimator()
        distanceEstimators[deviceId] = estimator
        return estimator
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
        pendingClusterRebuildTask?.cancel()
        pendingClusterRebuildTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.rebuildClusters()
        }
    }

    private func trimStoredObservationsIfNeeded() {
        guard observations.count > maximumStoredObservations else { return }
        observations.removeFirst(observations.count - maximumStoredObservations)
    }

    private func rebuildLiveOverview() {
        let visibleDevices = devices
            .filter { !$0.isIgnored }
            .sorted { $0.lastSeen > $1.lastSeen }

        guard !visibleDevices.isEmpty else {
            knownDeviceCategorySummaries = []
            return
        }

        let observationsByDevice = Dictionary(grouping: observations, by: \.deviceId)

        // Precompute classification for every visible device once, so we avoid
        // repeated calls to the classifier inside both grouping closures below.
        let classificationByDevice: [String: DetectedDeviceClassification] = Dictionary(
            uniqueKeysWithValues: visibleDevices.map { device in
                (device.id, classification(for: device, observations: observationsByDevice[device.id] ?? []))
            }
        )

        let classifiedDevices = visibleDevices.map { device in
            (
                device: device,
                classification: classificationByDevice[device.id] ?? DetectedDeviceClassification(
                    manufacturer: nil,
                    appearance: nil,
                    category: .unknown,
                    likelyProduct: nil,
                    confidence: 0,
                    evidence: []
                )
            )
        }

        let devicesByKnownCategory = Dictionary(grouping: classifiedDevices) { item in
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
                // Always push "Unknown" to the bottom.
                if $0.categoryName == "Unknown" { return false }
                if $1.categoryName == "Unknown" { return true }
                if $0.count == $1.count {
                    return $0.categoryName < $1.categoryName
                }
                return $0.count > $1.count
            }
    }

    private func preferredLocalName(for device: BluetoothDevice) -> String? {
        if let localAlias = device.localAlias, !localAlias.isEmpty {
            return localAlias
        }

        if let advertisedName = device.advertisedName, !advertisedName.isEmpty {
            return advertisedName
        }

        if let displayName = device.displayName, displayName != "Unknown BLE Device" {
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
