import CoreBluetooth
import Foundation

@MainActor
final class BluetoothScannerService: NSObject, ObservableObject {
    @Published private(set) var authorizationMessage = "Bluetooth permission has not been requested yet."
    @Published private(set) var bluetoothState = "Unknown"
    @Published private(set) var isScanning = false
    @Published private(set) var liveDevices: [BluetoothDevice] = []
    @Published private(set) var liveRSSI: [String: Int] = [:]

    var onObservation: ((ScanObservation, BluetoothDevice) -> Void)?

    private var centralManager: CBCentralManager?
    private var ignoredDeviceIds: Set<String> = []

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        updateAuthorizationMessage()
    }

    func startScanning() {
        guard let centralManager else { return }
        updateAuthorizationMessage()

        guard centralManager.state == .poweredOn else {
            bluetoothState = stateDescription(centralManager.state)
            return
        }

        liveDevices = []
        liveRSSI = [:]
        isScanning = true
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }

    func stopScanning() {
        centralManager?.stopScan()
        isScanning = false
    }

    func ignoreDevice(id: String) {
        ignoredDeviceIds.insert(id)
        liveDevices.removeAll { $0.id == id }
        liveRSSI[id] = nil
    }

    private func updateAuthorizationMessage() {
        switch CBCentralManager.authorization {
        case .allowedAlways:
            authorizationMessage = "Bluetooth scanning is allowed while the app is open."
        case .denied:
            authorizationMessage = "Bluetooth permission is denied. Enable it in Settings to scan nearby BLE advertisements."
        case .restricted:
            authorizationMessage = "Bluetooth access is restricted on this device."
        case .notDetermined:
            authorizationMessage = "Bluetooth permission will be requested when scanning starts."
        @unknown default:
            authorizationMessage = "Bluetooth permission state is unknown."
        }
    }

    private func stateDescription(_ state: CBManagerState) -> String {
        switch state {
        case .unknown:
            return "Unknown"
        case .resetting:
            return "Resetting"
        case .unsupported:
            return "Unsupported"
        case .unauthorized:
            return "Unauthorized"
        case .poweredOff:
            return "Powered off"
        case .poweredOn:
            return "Powered on"
        @unknown default:
            return "Unknown"
        }
    }
}

extension BluetoothScannerService: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            bluetoothState = stateDescription(central.state)
            updateAuthorizationMessage()

            if central.state != .poweredOn, isScanning {
                stopScanning()
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        Task { @MainActor in
            let deviceId = peripheral.identifier.uuidString
            guard !ignoredDeviceIds.contains(deviceId) else { return }

            let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
            let serviceUUIDs = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? [])
                .map(\.uuidString)
            let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
            let txPower = advertisementData[CBAdvertisementDataTxPowerLevelKey] as? Int
            let timestamp = Date()

            let device = BluetoothDevice(
                id: deviceId,
                displayName: advertisedName ?? peripheral.name ?? "Unknown BLE Device",
                advertisedName: advertisedName,
                firstSeen: liveDevices.first(where: { $0.id == deviceId })?.firstSeen ?? timestamp,
                lastSeen: timestamp,
                isIgnored: false,
                isMyDevice: false,
                localAlias: nil
            )

            let observation = ScanObservation(
                id: UUID(),
                deviceId: deviceId,
                timestamp: timestamp,
                rssi: RSSI.intValue,
                advertisedName: advertisedName,
                serviceUUIDs: serviceUUIDs,
                manufacturerDataSummary: manufacturerData.map(Self.manufacturerSummary),
                txPower: txPower
            )

            liveRSSI[deviceId] = RSSI.intValue
            if let index = liveDevices.firstIndex(where: { $0.id == deviceId }) {
                liveDevices[index] = device
            } else {
                liveDevices.append(device)
            }

            onObservation?(observation, device)
        }
    }

    private static func manufacturerSummary(_ data: Data) -> String {
        let prefix = data.prefix(12)
            .map { String(format: "%02X", $0) }
            .joined(separator: " ")

        if data.count > 12 {
            return "\(data.count) bytes: \(prefix) ..."
        }

        return "\(data.count) bytes: \(prefix)"
    }
}
