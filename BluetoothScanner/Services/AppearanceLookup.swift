import Foundation
import OSLog

struct AppearanceLookup {
    static let empty = AppearanceLookup(appearances: [])

    private static let logger = Logger(subsystem: "BluetoothScanner", category: "AppearanceLookup")

    private let appearancesById: [Int: BluetoothAppearance]

    init(bundle: Bundle = .main, resourceName: String = "gap_appearance", subdirectory: String? = "data") {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json", subdirectory: subdirectory) else {
            Self.logger.error("Missing bundled appearance JSON resource: \(resourceName).json")
            self.appearancesById = [:]
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let appearances = try JSONDecoder().decode([AppearanceCategoryRecord].self, from: data)
                .flatMap(BluetoothAppearance.makeAppearances(from:))
            self.appearancesById = Self.makeDictionary(from: appearances)
        } catch {
            Self.logger.error("Failed to load appearance JSON: \(error.localizedDescription)")
            self.appearancesById = [:]
        }
    }

    init(appearances: [BluetoothAppearance]) {
        appearancesById = Self.makeDictionary(from: appearances)
    }

    /// Loads the appearance catalog asynchronously, performing file I/O and JSON
    /// decoding off the calling thread. Safe to call from any concurrency context.
    static func loadFromBundle(
        bundle: Bundle = .main,
        resourceName: String = "gap_appearance",
        subdirectory: String? = "data"
    ) async -> AppearanceLookup {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json", subdirectory: subdirectory) else {
            logger.error("Missing bundled appearance JSON resource: \(resourceName).json")
            return .empty
        }

        do {
            let data = try Data(contentsOf: url)
            let appearances = try JSONDecoder().decode([AppearanceCategoryRecord].self, from: data)
                .flatMap(BluetoothAppearance.makeAppearances(from:))
            return AppearanceLookup(appearances: appearances)
        } catch {
            logger.error("Failed to load appearance JSON: \(error.localizedDescription)")
            return .empty
        }
    }

    private static func makeDictionary(from appearances: [BluetoothAppearance]) -> [Int: BluetoothAppearance] {
        var values: [Int: BluetoothAppearance] = [:]

        for appearance in appearances {
            guard values[appearance.appearanceId] == nil || values[appearance.appearanceId]?.description == "Unknown" else {
                continue
            }

            values[appearance.appearanceId] = appearance
        }

        return values
    }

    func appearance(for appearanceId: Int) -> BluetoothAppearance? {
        appearancesById[appearanceId]
    }

    func description(for appearanceId: Int) -> String? {
        appearance(for: appearanceId)?.description
    }
}

private struct AppearanceCategoryRecord: Decodable {
    let category: Int
    let name: String
    let subcategory: [AppearanceSubcategoryRecord]?
}

private struct AppearanceSubcategoryRecord: Decodable {
    let value: Int
    let name: String
}

private extension BluetoothAppearance {
    static func makeAppearances(from record: AppearanceCategoryRecord) -> [BluetoothAppearance] {
        let categoryAppearanceId = record.category << 6
        var appearances = [
            BluetoothAppearance(
                appearanceId: categoryAppearanceId,
                appearanceIdHex: String(format: "0x%04X", categoryAppearanceId),
                category: record.name,
                subcategory: nil,
                description: record.name
            )
        ]

        appearances.append(contentsOf: (record.subcategory ?? []).map { subcategory in
            let appearanceId = categoryAppearanceId | subcategory.value
            return BluetoothAppearance(
                appearanceId: appearanceId,
                appearanceIdHex: String(format: "0x%04X", appearanceId),
                category: record.name,
                subcategory: subcategory.name,
                description: subcategory.name
            )
        })

        return appearances
    }
}
