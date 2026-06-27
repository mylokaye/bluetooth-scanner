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
    static let empty = FuzzyManufacturerLookup(records: [], manufacturers: [])

    private static let logger = Logger(subsystem: "BluetoothScanner", category: "FuzzyManufacturerLookup")

    private let records: [ManufacturerNameMatchRecord]

    init(
        bundle: Bundle = .main,
        resourceName: String = "manufacturer_name_matches",
        companyResourceName: String = "company_ids",
        subdirectory: String? = "data"
    ) {
        var records: [ManufacturerNameMatchRecord] = []

        if let url = bundle.url(forResource: resourceName, withExtension: "json", subdirectory: subdirectory) {
            do {
                let data = try Data(contentsOf: url)
                records = try JSONDecoder().decode([ManufacturerNameMatchRecord].self, from: data)
            } catch {
                Self.logger.error("Failed to load manufacturer name match JSON: \(error.localizedDescription)")
            }
        } else {
            Self.logger.error("Missing bundled manufacturer name match JSON resource: \(resourceName).json")
        }

        var manufacturers: [BluetoothManufacturer] = []
        if let url = bundle.url(forResource: companyResourceName, withExtension: "json", subdirectory: subdirectory) {
            do {
                let data = try Data(contentsOf: url)
                manufacturers = try JSONDecoder().decode([CompanyIdentifierRecord].self, from: data)
                    .map(BluetoothManufacturer.init(record:))
            } catch {
                Self.logger.error("Failed to load manufacturer company JSON: \(error.localizedDescription)")
            }
        } else {
            Self.logger.error("Missing bundled manufacturer company JSON resource: \(companyResourceName).json")
        }

        self.records = Self.makeRecords(records: records, manufacturers: manufacturers)
    }

    init(records: [ManufacturerNameMatchRecord], manufacturers: [BluetoothManufacturer] = []) {
        self.records = Self.makeRecords(records: records, manufacturers: manufacturers)
    }

    func manufacturerName(for deviceName: String?) -> String? {
        guard let deviceName else { return nil }
        let normalizedDeviceName = Self.normalized(deviceName)
        guard !normalizedDeviceName.isEmpty else { return nil }

        let searchableDeviceName = " \(normalizedDeviceName) "
        return records.first { record in
            record.terms.contains { term in
                let normalizedTerm = Self.normalized(term)
                return !normalizedTerm.isEmpty && searchableDeviceName.contains(" \(normalizedTerm) ")
            }
        }?.manufacturer
    }

    private static func makeRecords(
        records: [ManufacturerNameMatchRecord],
        manufacturers: [BluetoothManufacturer]
    ) -> [ManufacturerNameMatchRecord] {
        records + manufacturers.compactMap(catalogRecord)
    }

    private static func catalogRecord(for manufacturer: BluetoothManufacturer) -> ManufacturerNameMatchRecord? {
        let terms = catalogTerms(for: manufacturer.manufacturer)
        guard !terms.isEmpty else { return nil }

        return ManufacturerNameMatchRecord(
            manufacturer: manufacturer.manufacturer,
            terms: terms
        )
    }

    private static func catalogTerms(for manufacturer: String) -> [String] {
        let withoutParentheticals = manufacturer
            .replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression)
        let splitCandidates = withoutParentheticals
            .split(separator: ",")
            .map(String.init)
        let candidates = ([withoutParentheticals] + splitCandidates)
            .map(strippingBusinessSuffixes)
            .map(normalized)
            .filter(isUsefulCatalogTerm)

        return Array(NSOrderedSet(array: candidates)) as? [String] ?? []
    }

    private static func strippingBusinessSuffixes(_ value: String) -> String {
        normalized(value)
            .replacingOccurrences(
                of: #"\b(incorporated|inc|limited|ltd|llc|corp|corporation|company|co|gmbh|ag|sa|sas|oy|bv|ab|as|plc|pte|pty|kg|srl|sro|spa|holdings|technology|technologies|electronics|international|industries)\b"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isUsefulCatalogTerm(_ term: String) -> Bool {
        guard !term.isEmpty else { return false }
        if term.count >= 4 { return true }

        let allowedShortTerms: Set<String> = ["3com", "avm", "bose", "dji", "hp", "ibm", "jbl", "lg", "nec", "tcl"]
        return allowedShortTerms.contains(term)
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
