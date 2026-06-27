import CoreBluetooth
import Foundation

@MainActor
final class BluetoothScannerService: NSObject, ObservableObject {
    @Published private(set) var authorizationMessage = "Bluetooth permission has not been requested yet."
    @Published private(set) var bluetoothState = "-"
    @Published private(set) var isScanning = false
    @Published private(set) var liveDevices: [BluetoothDevice] = []
    @Published private(set) var liveRSSI: [String: Int] = [:]

    var onObservation: ((ScanObservation, BluetoothDevice) -> Void)?

    private var centralManager: CBCentralManager?
    private var lastEmissionByDeviceId: [String: (date: Date, rssi: Int)] = [:]
    private var liveDeviceIndexById: [String: Int] = [:]
    private let minimumDuplicateEmissionInterval: TimeInterval = 1
    private let minimumRSSIDeltaForImmediateEmission = 6

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
        liveDeviceIndexById = [:]
        lastEmissionByDeviceId = [:]
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

    func clearLiveData() {
        stopScanning()
        liveDevices = []
        liveRSSI = [:]
        liveDeviceIndexById = [:]
        lastEmissionByDeviceId = [:]
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
            authorizationMessage = "Bluetooth permission state: -"
        }
    }

    private func stateDescription(_ state: CBManagerState) -> String {
        switch state {
        case .unknown:
            return "-"
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
            return "-"
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

            let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
            let deviceName = Self.meaningfulName(advertisedName) ?? Self.meaningfulName(peripheral.name)
            let serviceUUIDs = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? [])
                .map(\.uuidString)
            let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
            let manufacturerIdentifier = manufacturerData.flatMap(Self.manufacturerIdentifier)
            guard deviceName != nil || manufacturerIdentifier != nil else { return }

            let appearanceValue = (advertisementData["kCBAdvDataAppearance"] as? NSNumber)?.intValue
            let txPower = advertisementData[CBAdvertisementDataTxPowerLevelKey] as? Int
            let timestamp = Date()
            let rssi = RSSI.intValue

            let device = BluetoothDevice(
                id: deviceId,
                displayName: deviceName ?? "-",
                advertisedName: advertisedName,
                firstSeen: liveDevice(id: deviceId)?.firstSeen ?? timestamp,
                lastSeen: timestamp,
                isMyDevice: false,
                localAlias: nil
            )

            let shouldEmit = shouldEmitObservation(deviceId: deviceId, rssi: rssi, at: timestamp)
            guard shouldEmit else { return }

            liveRSSI[deviceId] = rssi
            upsertLiveDevice(device)

            let observation = ScanObservation(
                id: UUID(),
                deviceId: deviceId,
                timestamp: timestamp,
                rssi: rssi,
                advertisedName: advertisedName,
                serviceUUIDs: serviceUUIDs,
                manufacturerDataSummary: manufacturerData.map(Self.manufacturerSummary),
                manufacturerIdentifier: manufacturerIdentifier,
                appearanceValue: appearanceValue,
                txPower: txPower
            )

            onObservation?(observation, device)
        }
    }

    private func shouldEmitObservation(deviceId: String, rssi: Int, at timestamp: Date) -> Bool {
        guard let lastEmission = lastEmissionByDeviceId[deviceId] else {
            lastEmissionByDeviceId[deviceId] = (timestamp, rssi)
            return true
        }

        let elapsed = timestamp.timeIntervalSince(lastEmission.date)
        let rssiDelta = abs(rssi - lastEmission.rssi)
        let shouldEmit = elapsed >= minimumDuplicateEmissionInterval || rssiDelta >= minimumRSSIDeltaForImmediateEmission

        if shouldEmit {
            lastEmissionByDeviceId[deviceId] = (timestamp, rssi)
        }

        return shouldEmit
    }

    private func liveDevice(id: String) -> BluetoothDevice? {
        guard let index = liveDeviceIndexById[id] else { return nil }
        return liveDevices[index]
    }

    private func upsertLiveDevice(_ device: BluetoothDevice) {
        if let index = liveDeviceIndexById[device.id] {
            liveDevices[index] = device
        } else {
            liveDeviceIndexById[device.id] = liveDevices.count
            liveDevices.append(device)
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

    private static func meaningfulName(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedValue.isEmpty,
              trimmedValue != "-",
              trimmedValue != "Unknown",
              trimmedValue != "Unknown BLE Device"
        else {
            return nil
        }

        return trimmedValue
    }

    private static func manufacturerIdentifier(_ data: Data) -> String? {
        guard data.count >= 2 else { return nil }
        let identifier = UInt16(data[0]) | (UInt16(data[1]) << 8)
        return String(format: "%04X", identifier)
    }
}
