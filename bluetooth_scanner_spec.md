# Bluetooth  Scanner — iOS V1 Spec

## 1. Purpose

Build a simplified iOS SwiftUI app called **Bluetooth Scanner**.

The app scans nearby Bluetooth Low Energy devices while open, logs observations locally, identifies devices that may be trackable over time, and shows simple **Device Groups** based on devices that are commonly seen together.

The app is designed as a **bluetooth audit tool**.

## 2. Safety and bluetooth requirements

The app must:

Keep all data local on the device.
Not connect to, pair with, or interfere with Bluetooth devices.
Scan only while the app is active/open in V1.
Present all clustering as approximate and probabilistic.


## 3. V1 simplification

V1 should keep the app simple.

The app should include clustering logic, but should not include advanced cluster management controls.

### Include in V1

1. Live BLE scanning.
2. Local observation storage.
4. Automatic Device Groups with 1 phone and multiple devices which are commonly seen together.
5. Single-device groups with 1 phone.
6. RSSI-based distance categories for groups: Close / Nearby / Far / Weak
7. Basic user controls.

### Do not include in V1

1. Reject cluster.
2. Confirm cluster.
3. Rename cluster.
4. Merge cluster.
5. Split cluster.
6. Ignore cluster.
7. Manual cluster tagging.
8. Advanced scoring sliders.
11. Background always-on scanning.

## 4. Core user controls

Keep user controls simple.

### Required controls

1. Start scan.
2. Stop scan.
5. Ignore device.

## 5. Main app screens

## 5.1 Live Scan

Shows groups currently detected while the app is open.

## 5.3 Device Groups


The app should always show a Device Group for every discovered phone device.

A Device Group can contain:

1. A single phone device.
2. Multiple devices that are commonly seen together but must include a phone device.

### Display fields

1. Group type.
2. Devices in the group.
6. First seen.
7. Last seen.

### Single-device group example

```text
Device Group 1

Unknown BLE Device / Apple Phone
Device count: 1

```

### Multi-device group example

```text
Device Group

- Phone-like device
- Watch-like device
- Headphones-like device


```

### V1 limitation

The Device Groups screen is read-only in V1.


## 5.4 Device Detail

Shows more detail for one detected device.

### Display fields

1. Device metadata.
2. Advertised name.
3. Local device identifier.
8. First seen.
9. Last seen.


## 6. Bluetooth scanning requirements

Use **CoreBluetooth** with `CBCentralManager`.

The app should:

1. Scan for BLE peripherals while active.
2. Allow duplicate scan results so RSSI updates live.
3. Request Bluetooth permission using `NSBluetoothAlwaysUsageDescription`.
4. Capture observations without connecting or pairing.

### Capture these fields

1. Peripheral identifier.
2. Peripheral name.
3. RSSI.
4. Service UUIDs.
5. Manufacturer data summary.
6. TX power, if available.
7. Timestamp.

## 7. Local storage

Use local JSON storage for V1.

The code should be structured so storage can move to SQLite later without rewriting the app.

All data must remain local on the device.

## 8. Session logic

Create rolling scan sessions.

### Default session behaviour

2. Devices seen within the same window count as co-present.
3. Store session membership locally.

## 9. Device Group logic

Device Groups are automatic and read-only in V1.

### Required behaviour

1. Every discovered non-ignored device must appear in at least one Device Group.
2. If a device has no strong association with other devices, create a single-device group.
3. If two or more devices are repeatedly seen together, create or upgrade to a commonly-seen-together group.
4. Do not show a group unless it has at least one phone device.

### Single-device group rules

Single-device groups should have:

1. `clusterType: singleDevice`
2. `confidenceLabel: low`
3. `confidenceScore` between `0.1` and `0.3`
4. `seenTogetherCount: 1`
5. A reason explaining that no strong related devices have been detected yet.

### Multi-device group rules

Multi-device groups should have:

1. `clusterType: commonlySeenTogether`
2. A confidence score based on evidence.
3. A confidence label of low, medium, or high.

### Multi-device confidence inputs

Use these inputs where enough data exists:

1. Co-presence in scan sessions.
2. Repeated co-presence count.
3. RSSI trend similarity.
4. Arrival timing similarity.
5. Departure timing similarity.



## 11. Data models

## 11.1 BluetoothDevice

```swift
struct BluetoothDevice: Identifiable, Codable, Hashable {
    let id: String
    var displayName: String?
    var advertisedName: String?
    var firstSeen: Date
    var lastSeen: Date
    var isIgnored: Bool
    var isMyDevice: Bool
    var localAlias: String?
}
```

## 11.2 ScanObservation

```swift
struct ScanObservation: Identifiable, Codable {
    let id: UUID
    let deviceId: String
    let timestamp: Date
    let rssi: Int
    let advertisedName: String?
    let serviceUUIDs: [String]
    let manufacturerDataSummary: String?
    let txPower: Int?
}
```

## 11.3 ScanSession

```swift
struct ScanSession: Identifiable, Codable {
    let id: UUID
    let startedAt: Date
    var endedAt: Date?
    var deviceIds: Set<String>
}
```

## 11.4 DeviceCluster

```swift
struct DeviceCluster: Identifiable, Codable {
    let id: UUID
    var deviceIds: [String]
    var clusterType: ClusterType
    var confidenceScore: Double
    var confidenceLabel: ConfidenceLabel
    var seenTogetherCount: Int
    var firstSeen: Date
    var lastSeen: Date
    var reasons: [String]
}

enum ClusterType: String, Codable {
    case singleDevice
    case commonlySeenTogether
}

enum ConfidenceLabel: String, Codable {
    case low
    case medium
    case high
}
```


```

## 12. Required architecture

Use this folder structure:

```text
Models/
Services/
Views/
```

### Required service files

```text
Services/BluetoothScannerService.swift
Services/ClusterDetectionService.swift
Services/LocalStorageService.swift
Services/SessionService.swift
```

### Required view files

```text
Views/LiveScanView.swift
Views/DeviceGroupsView.swift
Views/DeviceDetailView.swift
Views/SettingsView.swift
```

## 13. Safe UI wording

Use these exact or near-exact phrases throughout the app:

```text
This device appears repeatedly and broadcasts a stable identifier.
```

```text
It may be trackable over time by nearby Bluetooth scanners.
```

```text
These devices are commonly seen together.
```



## 14. Recommended build order

1. Live BLE scan.
2. Local observation storage.
3. Session grouping.
5. Single-device Device Groups.
6. Multi-device Device Groups.
7. Device detail view.

