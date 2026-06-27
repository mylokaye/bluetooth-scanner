import Foundation
import OSLog

struct ManufacturerLookup {
    static let empty = ManufacturerLookup(manufacturers: [])

    private static let logger = Logger(subsystem: "BluetoothScanner", category: "ManufacturerLookup")

    private let manufacturersByCompanyId: [Int: BluetoothManufacturer]

    init(bundle: Bundle = .main, resourceName: String = "company_ids", subdirectory: String? = "data") {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json", subdirectory: subdirectory) else {
            Self.logger.error("Missing bundled manufacturer JSON resource: \(resourceName).json")
            self.manufacturersByCompanyId = [:]
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let manufacturers = try JSONDecoder().decode([CompanyIdentifierRecord].self, from: data)
                .map(BluetoothManufacturer.init(record:))
            self.manufacturersByCompanyId = Self.makeDictionary(from: manufacturers)
        } catch {
            Self.logger.error("Failed to load manufacturer JSON: \(error.localizedDescription)")
            self.manufacturersByCompanyId = [:]
        }
    }

    init(manufacturers: [BluetoothManufacturer]) {
        manufacturersByCompanyId = Self.makeDictionary(from: manufacturers)
    }

    /// Loads the manufacturer catalog asynchronously, performing file I/O and JSON
    /// decoding off the calling thread. Safe to call from any concurrency context.
    static func loadFromBundle(
        bundle: Bundle = .main,
        resourceName: String = "company_ids",
        subdirectory: String? = "data"
    ) async -> ManufacturerLookup {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json", subdirectory: subdirectory) else {
            logger.error("Missing bundled manufacturer JSON resource: \(resourceName).json")
            return .empty
        }

        do {
            let data = try Data(contentsOf: url)
            let manufacturers = try JSONDecoder().decode([CompanyIdentifierRecord].self, from: data)
                .map(BluetoothManufacturer.init(record:))
            return ManufacturerLookup(manufacturers: manufacturers)
        } catch {
            logger.error("Failed to load manufacturer JSON: \(error.localizedDescription)")
            return .empty
        }
    }

    private static func makeDictionary(from manufacturers: [BluetoothManufacturer]) -> [Int: BluetoothManufacturer] {
        Dictionary(
            manufacturers.map { ($0.companyId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    func manufacturerName(for companyId: Int) -> String? {
        manufacturer(for: companyId)?.manufacturer
    }

    func manufacturer(for companyId: Int) -> BluetoothManufacturer? {
        manufacturersByCompanyId[companyId]
    }
}

struct FuzzyManufacturerLookup {
    static let empty = FuzzyManufacturerLookup(records: [])

    private static let logger = Logger(subsystem: "BluetoothScanner", category: "FuzzyManufacturerLookup")

    private let records: [ManufacturerNameMatchRecord]

    init(bundle: Bundle = .main, resourceName: String = "manufacturer_name_matches", subdirectory: String? = "data") {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json", subdirectory: subdirectory) else {
            Self.logger.error("Missing bundled manufacturer name match JSON resource: \(resourceName).json")
            self.records = []
            return
        }

        do {
            let data = try Data(contentsOf: url)
            self.records = try JSONDecoder().decode([ManufacturerNameMatchRecord].self, from: data)
        } catch {
            Self.logger.error("Failed to load manufacturer name match JSON: \(error.localizedDescription)")
            self.records = []
        }
    }

    init(records: [ManufacturerNameMatchRecord]) {
        self.records = records
    }

    func manufacturerName(for deviceName: String?) -> String? {
        guard let deviceName else { return nil }
        let normalizedDeviceName = Self.normalized(deviceName)
        guard !normalizedDeviceName.isEmpty else { return nil }

        return records.first { record in
            record.terms.contains { term in
                let normalizedTerm = Self.normalized(term)
                return !normalizedTerm.isEmpty && normalizedDeviceName.contains(normalizedTerm)
            }
        }?.manufacturer
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }
}

private struct CompanyIdentifierRecord: Decodable {
    let code: Int
    let name: String
}

struct ManufacturerNameMatchRecord: Decodable {
    let manufacturer: String
    let terms: [String]
}

private extension BluetoothManufacturer {
    init(record: CompanyIdentifierRecord) {
        self.init(
            companyId: record.code,
            companyIdHex: String(format: "0x%04X", record.code),
            manufacturer: record.name
        )
    }
}
