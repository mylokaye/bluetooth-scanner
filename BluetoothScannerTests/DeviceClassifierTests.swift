import XCTest
@testable import BluetoothScanner

final class DeviceClassifierTests: XCTestCase {
    func testManufacturerLookupFindsAppleByCompanyId() {
        let lookup = ManufacturerLookup(
            manufacturers: [
                BluetoothManufacturer(companyId: 76, companyIdHex: "0x004C", manufacturer: "Apple, Inc.")
            ]
        )

        XCTAssertEqual(lookup.manufacturerName(for: 76), "Apple, Inc.")
    }

    func testUnknownManufacturerReturnsNil() {
        let lookup = ManufacturerLookup(
            manufacturers: [
                BluetoothManufacturer(companyId: 76, companyIdHex: "0x004C", manufacturer: "Apple, Inc.")
            ]
        )

        XCTAssertNil(lookup.manufacturerName(for: 999_999))
    }

    func testManufacturerLookupFindsSamsungByCompanyId() {
        let lookup = ManufacturerLookup(
            manufacturers: [
                BluetoothManufacturer(companyId: 117, companyIdHex: "0x0075", manufacturer: "Samsung Electronics Co. Ltd.")
            ]
        )

        XCTAssertEqual(lookup.manufacturerName(for: 117), "Samsung Electronics Co. Ltd.")
    }

    func testAppearanceLookupFindsKnownAppearanceValue() {
        let lookup = AppearanceLookup(
            appearances: [
                BluetoothAppearance(
                    appearanceId: 1,
                    appearanceIdHex: "0x0001",
                    category: "Phone",
                    subcategory: nil,
                    description: "Phone"
                )
            ]
        )

        XCTAssertEqual(lookup.description(for: 1), "Phone")
    }

    func testDeviceClassifierIdentifiesAppleWatch() {
        let classifier = DeviceClassifier(
            manufacturerLookup: ManufacturerLookup(
                manufacturers: [
                    BluetoothManufacturer(companyId: 76, companyIdHex: "0x004C", manufacturer: "Apple, Inc.")
                ]
            ),
            appearanceLookup: AppearanceLookup(
                appearances: [
                    BluetoothAppearance(
                        appearanceId: 6,
                        appearanceIdHex: "0x0006",
                        category: "Wearable computer (watch size)",
                        subcategory: nil,
                        description: "Wearable computer (watch size)"
                    )
                ]
            )
        )

        let result = classifier.classify(
            BluetoothAdvertisementSnapshot(
                localName: "My Apple Watch",
                manufacturerCompanyId: 76,
                appearanceId: 6,
                serviceUUIDs: []
            )
        )

        XCTAssertEqual(result.manufacturer, "Apple, Inc.")
        XCTAssertEqual(result.category, .watch)
        XCTAssertEqual(result.likelyProduct, "Apple Watch")
        XCTAssertGreaterThanOrEqual(result.confidence, 85)
    }

    func testDeviceClassifierIdentifiesAirPodsFromName() {
        let classifier = DeviceClassifier(
            manufacturerLookup: .empty,
            appearanceLookup: .empty
        )

        let result = classifier.classify(
            BluetoothAdvertisementSnapshot(
                localName: "My AirPods Pro",
                manufacturerCompanyId: nil,
                appearanceId: nil,
                serviceUUIDs: []
            )
        )

        XCTAssertEqual(result.category, .headphones)
        XCTAssertEqual(result.confidence, 20)
    }

    func testDeviceClassifierReturnsUnknownForWeakData() {
        let classifier = DeviceClassifier(
            manufacturerLookup: .empty,
            appearanceLookup: .empty
        )

        let result = classifier.classify(
            BluetoothAdvertisementSnapshot(
                localName: nil,
                manufacturerCompanyId: nil,
                appearanceId: nil,
                serviceUUIDs: []
            )
        )

        XCTAssertEqual(result.category, .unknown)
        XCTAssertNil(result.manufacturer)
        XCTAssertNil(result.appearance)
        XCTAssertEqual(result.confidence, 0)
    }

    func testConfidenceIsClampedBetweenZeroAndOneHundred() {
        let classifier = DeviceClassifier(
            manufacturerLookup: ManufacturerLookup(
                manufacturers: [
                    BluetoothManufacturer(companyId: 76, companyIdHex: "0x004C", manufacturer: "Apple, Inc.")
                ]
            ),
            appearanceLookup: AppearanceLookup(
                appearances: [
                    BluetoothAppearance(
                        appearanceId: 1,
                        appearanceIdHex: "0x0001",
                        category: "Phone",
                        subcategory: nil,
                        description: "Phone"
                    )
                ]
            )
        )

        let result = classifier.classify(
            BluetoothAdvertisementSnapshot(
                localName: "iPhone",
                manufacturerCompanyId: 76,
                appearanceId: 1,
                serviceUUIDs: ["180E"]
            )
        )

        XCTAssertGreaterThanOrEqual(result.confidence, 0)
        XCTAssertLessThanOrEqual(result.confidence, 100)
    }

    func testMissingJSONFileDoesNotCrashLookupService() {
        let lookup = ManufacturerLookup(
            bundle: Bundle(for: DeviceClassifierTests.self),
            resourceName: "missing_bluetooth_manufacturers"
        )

        XCTAssertNil(lookup.manufacturerName(for: 76))
    }
}
