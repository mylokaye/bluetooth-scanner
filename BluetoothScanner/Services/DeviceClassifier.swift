import Foundation

struct DeviceClassifier {
    private let manufacturerLookup: ManufacturerLookup
    private let appearanceLookup: AppearanceLookup

    init(
        manufacturerLookup: ManufacturerLookup = ManufacturerLookup(),
        appearanceLookup: AppearanceLookup = AppearanceLookup()
    ) {
        self.manufacturerLookup = manufacturerLookup
        self.appearanceLookup = appearanceLookup
    }

    func classify(_ snapshot: BluetoothAdvertisementSnapshot) -> DetectedDeviceClassification {
        var evidence: [ClassificationEvidence] = []
        var category: DeviceCategory = .unknown

        let manufacturer = snapshot.manufacturerCompanyId.flatMap {
            manufacturerLookup.manufacturerName(for: $0)
        }

        if let manufacturer {
            evidence.append(
                ClassificationEvidence(
                    source: "Manufacturer",
                    value: manufacturer,
                    confidenceContribution: 30
                )
            )
        }

        let appearance = snapshot.appearanceId.flatMap {
            appearanceLookup.appearance(for: $0)
        }

        if let appearance {
            let appearanceText = [appearance.category, appearance.subcategory, appearance.description]
                .compactMap { $0 }
                .joined(separator: " ")

            if let appearanceCategory = categoryFromAppearanceText(appearanceText) {
                category = appearanceCategory
            }

            evidence.append(
                ClassificationEvidence(
                    source: "Appearance",
                    value: appearance.description,
                    confidenceContribution: 35
                )
            )
        }

        if let localName = snapshot.localName,
           let nameCategory = categoryFromName(localName) {
            category = nameCategory
            evidence.append(
                ClassificationEvidence(
                    source: "Name",
                    value: localName,
                    confidenceContribution: 20
                )
            )
        }

        if let serviceCategory = categoryFromServices(snapshot.serviceUUIDs) {
            if category == .unknown {
                category = serviceCategory
            }

            evidence.append(
                ClassificationEvidence(
                    source: "Service UUID",
                    value: snapshot.serviceUUIDs.joined(separator: ", "),
                    confidenceContribution: 15
                )
            )
        }

        let likelyProduct = likelyProduct(
            manufacturer: manufacturer,
            localName: snapshot.localName,
            appearance: appearance,
            category: category
        )

        // BLE advertisements are intentionally sparse. Manufacturer IDs identify a vendor,
        // not a product, so product guesses are only made when name or appearance agrees.
        let confidence = min(100, max(0, evidence.map(\.confidenceContribution).reduce(0, +)))

        return DetectedDeviceClassification(
            manufacturer: manufacturer,
            appearance: appearance?.description,
            category: category,
            likelyProduct: likelyProduct,
            confidence: confidence,
            evidence: evidence
        )
    }

    private func categoryFromName(_ name: String) -> DeviceCategory? {
        let value = name.lowercased()

        if value.contains("iphone") ||
            value.contains("myphone") ||
            value.contains("android") ||
            value.contains("pixel") ||
            value.contains("galaxy") && !value.contains("buds") {
            return .phone
        }

        if value.contains("airpods") ||
            value.contains("buds") ||
            value.contains("headphone") ||
            value.contains("headset") ||
            value.contains("beats") {
            return .headphones
        }

        if value.contains("watch") {
            return .watch
        }

        if value.contains("keyboard") {
            return .keyboard
        }

        if value.contains("mouse") {
            return .mouse
        }

        if value.contains("tile") ||
            value.contains("tracker") ||
            value.contains("airtag") {
            return .tracker
        }

        if value.contains("fitbit") ||
            value.contains("garmin") {
            return .wearable
        }

        if value.contains("macbook") ||
            value.contains("ipad") ||
            value.contains("laptop") ||
            value.contains("computer") ||
            value.contains("pc") {
            return .computer
        }

        if value.contains("tv") ||
            value.contains("bravia") ||
            value.contains("chromecast") ||
            value.contains("roku") ||
            value.contains("webos") {
            return .tv
        }

        // Screen-size patterns like 50", 55 inch, 65-inch suggest a TV.
        if value.range(of: #"\d{2,}\s*(?:inch|\")"#, options: .regularExpression) != nil {
            return .tv
        }

        if value.contains("hue") {
            return .lighting
        }

        return nil
    }

    private func categoryFromAppearanceText(_ text: String) -> DeviceCategory? {
        let value = text.lowercased()

        if value.contains("phone") {
            return .phone
        }

        if value.contains("watch") {
            return .watch
        }

        if value.contains("headset") ||
            value.contains("earbud") ||
            value.contains("audio") ||
            value.contains("speaker") {
            return .headphones
        }

        if value.contains("computer") ||
            value.contains("workstation") ||
            value.contains("laptop") ||
            value.contains("tablet") {
            return .computer
        }

        if value.contains("keyboard") {
            return .keyboard
        }

        if value.contains("mouse") {
            return .mouse
        }

        if value.contains("heart rate") ||
            value.contains("blood pressure") ||
            value.contains("pulse") ||
            value.contains("cycling") ||
            value.contains("running") {
            return .health
        }

        if value.contains("wearable") {
            return .wearable
        }

        if value.contains("car") ||
            value.contains("vehicle") {
            return .vehicle
        }

        if value.contains("television") ||
            value.contains("tv") ||
            value.contains("monitor") {
            return .tv
        }

        return nil
    }

    private func categoryFromServices(_ serviceUUIDs: [String]) -> DeviceCategory? {
        let services = Set(serviceUUIDs.map { normalizedServiceUUID($0) })

        if services.contains("180D") ||
            services.contains("1814") ||
            services.contains("1816") ||
            services.contains("181D") {
            return .health
        }

        if services.contains("1812") {
            return .keyboard
        }

        if services.contains("180E") ||
            services.contains("180F") && services.contains("180A") {
            return .phone
        }

        if services.contains("FE2C") {
            return .tracker
        }

        return nil
    }

    private func likelyProduct(
        manufacturer: String?,
        localName: String?,
        appearance: BluetoothAppearance?,
        category: DeviceCategory
    ) -> String? {
        let maker = manufacturer?.lowercased() ?? ""
        let name = localName?.lowercased() ?? ""
        let appearanceText = [
            appearance?.category,
            appearance?.subcategory,
            appearance?.description
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")

        if maker.contains("apple") {
            if name.contains("airpods") {
                return "AirPods"
            }

            if name.contains("watch") || appearanceText.contains("watch") || category == .watch {
                return "Apple Watch"
            }

            if category == .phone || appearanceText.contains("phone") {
                return "iPhone"
            }
        }

        if maker.contains("samsung") {
            if name.contains("buds") {
                return "Samsung Galaxy Buds"
            }

            if category == .tv {
                return "Samsung TV"
            }
        }

        if maker.contains("garmin"), category == .wearable || category == .health || appearanceText.contains("watch") {
            return "Garmin wearable"
        }

        if maker.contains("fitbit"), category == .wearable || category == .health {
            return "Fitbit wearable"
        }

        if maker.contains("philips") || name.contains("hue") {
            return "Philips Hue"
        }

        return nil
    }

    private func normalizedServiceUUID(_ uuid: String) -> String {
        uuid
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "0X", with: "")
    }
}
