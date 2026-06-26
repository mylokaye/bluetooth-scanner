import Foundation
import OSLog

struct AppearanceLookup {
    static let empty = AppearanceLookup(appearances: [])

    private static let logger = Logger(subsystem: "BluetoothScanner", category: "AppearanceLookup")

    private let appearancesById: [Int: BluetoothAppearance]

    init(bundle: Bundle = .main, resourceName: String = "bluetooth_appearances") {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            Self.logger.error("Missing bundled appearance JSON resource: \(resourceName).json")
            self.appearancesById = [:]
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let appearances = try JSONDecoder().decode([BluetoothAppearance].self, from: data)
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
        resourceName: String = "bluetooth_appearances"
    ) async -> AppearanceLookup {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            logger.error("Missing bundled appearance JSON resource: \(resourceName).json")
            return .empty
        }

        do {
            let data = try Data(contentsOf: url)
            let appearances = try JSONDecoder().decode([BluetoothAppearance].self, from: data)
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
