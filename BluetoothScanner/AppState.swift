import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var devices: [BluetoothDevice] = []
    @Published private(set) var observations: [ScanObservation] = []
    @Published private(set) var sessions: [ScanSession] = []
    @Published private(set) var clusters: [DeviceCluster] = []
    @Published private(set) var deviceCategorySummaries: [DeviceCategorySummary] = []
    @Published private(set) var knownDeviceCategorySummaries: [KnownDeviceCategorySummary] = []
    @Published var lastStorageError: String?

    let scanner = BluetoothScannerService()

    private let storage = LocalStorageService()
    private let udidCatalog: UDIDCatalog
    private let manufacturerCatalog: ManufacturerIdentifierCatalog
    private let appearanceCatalog: AppearanceCatalog
    private var sessionService = SessionService()
    private let clusterService = ClusterDetectionService()
    private var cancellables: Set<AnyCancellable> = []
    private var pendingSaveTask: Task<Void, Never>?
    private var pendingClusterRebuildTask: Task<Void, Never>?
    private var distanceEstimators: [String: BLEDistanceEstimator] = [:]
    private let maximumStoredObservations = 5_000

    init() {
        if let csvURL = Bundle.main.url(forResource: "UDID", withExtension: "csv"),
           let catalog = try? UDIDCatalog(csvURL: csvURL) {
            udidCatalog = catalog
        } else {
            udidCatalog = .empty
        }
        if let csvURL = Bundle.main.url(forResource: "manufacturer", withExtension: "csv"),
           let catalog = try? ManufacturerIdentifierCatalog(csvURL: csvURL) {
            manufacturerCatalog = catalog
        } else {
            manufacturerCatalog = .empty
        }
        if let csvURL = Bundle.main.url(forResource: "appearance_values", withExtension: "csv"),
           let catalog = try? AppearanceCatalog(csvURL: csvURL) {
            appearanceCatalog = catalog
        } else {
            appearanceCatalog = .empty
        }

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
            rebuildDistanceEstimators()
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
        pendingSaveTask?.cancel()
        devices = []
        observations = []
        sessions = []
        clusters = []
        deviceCategorySummaries = []
        knownDeviceCategorySummaries = []
        distanceEstimators = [:]
        sessionService.reset()

        Task {
            await save()
        }
    }

    func ignore(device: BluetoothDevice) {
        guard let index = devices.firstIndex(where: { $0.id == device.id }) else { return }
        devices[index].isIgnored = true
        scanner.ignoreDevice(id: device.id)
        distanceEstimators[device.id] = nil
        pendingClusterRebuildTask?.cancel()
        rebuildClusters()
        rebuildLiveOverview()
        scheduleSave()
    }

    func device(id: String) -> BluetoothDevice? {
        devices.first { $0.id == id } ?? scanner.liveDevices.first { $0.id == id }
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

    func devices(in category: DeviceCategory) -> [BluetoothDevice] {
        let observationsByDevice = Dictionary(grouping: observations, by: \.deviceId)

        return devices
            .filter { !$0.isIgnored }
            .filter { device in
                DeviceCategory.infer(for: device, observations: observationsByDevice[device.id] ?? []) == category
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

    func classification(for device: BluetoothDevice) -> DeviceClassification {
        let deviceObservations = observations(for: device.id)
        return classification(for: device, observations: deviceObservations)
    }

    private func classification(for device: BluetoothDevice, observations deviceObservations: [ScanObservation]) -> DeviceClassification {
        let latestObservations = deviceObservations.sorted { $0.timestamp > $1.timestamp }
        let inferredCategory = DeviceCategory.infer(for: device, observations: deviceObservations)
        let entry = udidCatalog.entry(for: deviceObservations.flatMap(\.serviceUUIDs))
        let latestManufacturerIdentifier = latestObservations.lazy.compactMap(\.manufacturerIdentifier).first
        let latestAppearanceValue = latestObservations.lazy.compactMap(\.appearanceValue).first
        let manufacturerName = manufacturerCatalog.manufacturerName(for: latestManufacturerIdentifier) ?? entry?.company
        let appearanceName = appearanceCatalog.appearanceName(for: latestAppearanceValue)
        let categoryName = appearanceName ?? inferredCategory.title

        return DeviceClassification(
            categoryName: categoryName,
            manufacturerName: manufacturerName,
            symbolName: symbolName(forCategory: categoryName, fallback: inferredCategory),
            matchedUUID: entry?.uuid,
            manufacturerIdentifier: latestManufacturerIdentifier,
            appearanceName: appearanceName,
            appearanceValue: latestAppearanceValue,
            inferredCategory: inferredCategory
        )
    }

    private func record(observation: ScanObservation, device incomingDevice: BluetoothDevice) async {
        let device = merge(device: incomingDevice)
        estimator(for: device.id).update(rssi: observation.rssi, at: observation.timestamp)
        observations.append(observation)
        trimStoredObservationsIfNeeded()
        sessionService.record(deviceId: device.id, at: observation.timestamp)
        sessions = sessionService.sessions
        rebuildLiveOverview()
        scheduleClusterRebuild()
        scheduleSave()
    }

    @discardableResult
    private func merge(device incomingDevice: BluetoothDevice) -> BluetoothDevice {
        if let index = devices.firstIndex(where: { $0.id == incomingDevice.id }) {
            devices[index].displayName = incomingDevice.displayName ?? devices[index].displayName
            devices[index].advertisedName = incomingDevice.advertisedName ?? devices[index].advertisedName
            devices[index].lastSeen = max(devices[index].lastSeen, incomingDevice.lastSeen)
            return devices[index]
        } else {
            devices.append(incomingDevice)
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

    private func rebuildDistanceEstimators() {
        distanceEstimators = [:]
        let observationsByDevice = Dictionary(grouping: observations, by: \.deviceId)

        for (deviceId, deviceObservations) in observationsByDevice {
            let estimator = estimator(for: deviceId)
            deviceObservations
                .sorted { $0.timestamp < $1.timestamp }
                .suffix(10)
                .forEach { observation in
                    estimator.update(rssi: observation.rssi, at: observation.timestamp)
                }
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

    private func scheduleClusterRebuild() {
        pendingClusterRebuildTask?.cancel()
        pendingClusterRebuildTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await self?.rebuildClusters()
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
        let observationsByDevice = Dictionary(grouping: observations, by: \.deviceId)
        let devicesByCategory = Dictionary(grouping: visibleDevices) { device in
            DeviceCategory.infer(for: device, observations: observationsByDevice[device.id] ?? [])
        }

        deviceCategorySummaries = DeviceCategory.allCases.compactMap { category in
            guard let devices = devicesByCategory[category], !devices.isEmpty else { return nil }
            return DeviceCategorySummary(
                category: category,
                count: devices.count,
                lastSeen: devices.map(\.lastSeen).max()
            )
        }

        let classifiedDevices = visibleDevices.map { device in
            (
                device: device,
                classification: classification(
                    for: device,
                    observations: observationsByDevice[device.id] ?? []
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
                if $0.count == $1.count {
                    return $0.categoryName < $1.categoryName
                }
                return $0.count > $1.count
            }
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

    private func symbolName(forCategory category: String?, fallback: DeviceCategory) -> String {
        guard let category = category?.lowercased() else {
            return fallback.symbolName
        }

        if category.contains("audio") {
            return "headphones"
        }
        if category.contains("phone") {
            return "iphone"
        }
        if category.contains("laptop") ||
            category.contains("computer") ||
            category.contains("workstation") ||
            category.contains("pc") {
            return "laptopcomputer"
        }
        if category.contains("tablet") {
            return "ipad"
        }
        if category.contains("wearable") || category.contains("watch") {
            return "applewatch"
        }
        if category.contains("display") || category.contains("tv") {
            return "tv"
        }
        if category.contains("keyboard") {
            return "keyboard"
        }
        if category.contains("mouse") {
            return "computermouse"
        }
        if category.contains("smart home") || category.contains("home") {
            return "house"
        }
        if category.contains("vehicle") {
            return "car"
        }
        if category.contains("health") {
            return "cross.case"
        }
        if category.contains("security") {
            return "lock.shield"
        }
        if category.contains("industrial") || category.contains("tools") {
            return "wrench.and.screwdriver"
        }
        if category.contains("software") {
            return "terminal"
        }
        if category.contains("chip") {
            return "cpu"
        }
        if category.contains("apple") {
            return "apple.logo"
        }
        if category.contains("electronics") {
            return "sensor.tag.radiowaves.forward"
        }

        return fallback.symbolName
    }
}
