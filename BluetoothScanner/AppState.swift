import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var devices: [BluetoothDevice] = []
    @Published private(set) var observations: [ScanObservation] = []
    @Published private(set) var sessions: [ScanSession] = []
    @Published private(set) var clusters: [DeviceCluster] = []
    @Published var lastStorageError: String?

    let scanner = BluetoothScannerService()

    private let storage = LocalStorageService()
    private var sessionService = SessionService()
    private let clusterService = ClusterDetectionService()
    private var cancellables: Set<AnyCancellable> = []

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
            rebuildClusters()
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
        rebuildClusters()
        Task {
            await save()
        }
    }

    func ignore(device: BluetoothDevice) {
        guard let index = devices.firstIndex(where: { $0.id == device.id }) else { return }
        devices[index].isIgnored = true
        scanner.ignoreDevice(id: device.id)
        rebuildClusters()
        Task {
            await save()
        }
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

    private func record(observation: ScanObservation, device incomingDevice: BluetoothDevice) async {
        let device = merge(device: incomingDevice)
        observations.append(observation)
        sessionService.record(deviceId: device.id, at: observation.timestamp)
        sessions = sessionService.sessions
        rebuildClusters()
        await save()
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
