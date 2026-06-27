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

    private struct IndexedTerm {
        let manufacturer: String
        let term: String
        let order: Int
    }

    private final class LookupCache {
        private var hits: [String: String] = [:]
        private var misses: Set<String> = []
        private let lock = NSLock()

        func value(for key: String) -> String?? {
            lock.lock()
            defer { lock.unlock() }

            if let hit = hits[key] {
                return .some(hit)
            }

            if misses.contains(key) {
                return .some(nil)
            }

            return nil
        }

        func store(_ value: String?, for key: String) {
            lock.lock()
            defer { lock.unlock() }

            if let value {
                hits[key] = value
                misses.remove(key)
            } else {
                hits[key] = nil
                misses.insert(key)
            }
        }
    }

    private static let logger = Logger(subsystem: "BluetoothScanner", category: "FuzzyManufacturerLookup")

    private let termsByFirstToken: [String: [IndexedTerm]]
    private let cache = LookupCache()

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

        self.termsByFirstToken = Self.makeIndex(records: Self.makeRecords(records: records, manufacturers: manufacturers))
    }

    init(records: [ManufacturerNameMatchRecord], manufacturers: [BluetoothManufacturer] = []) {
        self.termsByFirstToken = Self.makeIndex(records: Self.makeRecords(records: records, manufacturers: manufacturers))
    }

    func manufacturerName(for deviceName: String?) -> String? {
        let startedAt = Date()
        guard let deviceName else { return nil }
        let normalizedDeviceName = Self.normalized(deviceName)
        guard !normalizedDeviceName.isEmpty else { return nil }
        if let cached = cache.value(for: normalizedDeviceName) {
            return cached
        }

        let searchableDeviceName = " \(normalizedDeviceName) "
        let candidateTerms = Set(normalizedDeviceName.split(separator: " ").map(String.init))
            .flatMap { termsByFirstToken[$0] ?? [] }
            .sorted { lhs, rhs in
                if lhs.order == rhs.order {
                    return lhs.term.count > rhs.term.count
                }
                return lhs.order < rhs.order
            }

        let manufacturer = candidateTerms.first { indexedTerm in
            searchableDeviceName.contains(" \(indexedTerm.term) ")
        }?.manufacturer
        cache.store(manufacturer, for: normalizedDeviceName)
        Self.logDuration("fuzzy manufacturer lookup", since: startedAt)
        return manufacturer
    }

    private static func makeRecords(
        records: [ManufacturerNameMatchRecord],
        manufacturers: [BluetoothManufacturer]
    ) -> [ManufacturerNameMatchRecord] {
        records + manufacturers.compactMap(catalogRecord)
    }

    private static func makeIndex(records: [ManufacturerNameMatchRecord]) -> [String: [IndexedTerm]] {
        var termsByFirstToken: [String: [IndexedTerm]] = [:]
        var seenTerms: Set<String> = []

        for (recordIndex, record) in records.enumerated() {
            for rawTerm in record.terms {
                let term = normalized(rawTerm)
                guard !term.isEmpty,
                      let firstToken = term.split(separator: " ").first.map(String.init)
                else { continue }

                let termKey = "\(record.manufacturer)|\(term)"
                guard seenTerms.insert(termKey).inserted else { continue }

                termsByFirstToken[firstToken, default: []].append(
                    IndexedTerm(
                        manufacturer: record.manufacturer,
                        term: term,
                        order: recordIndex
                    )
                )
            }
        }

        return termsByFirstToken
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

    private static func logDuration(_ operation: StaticString, since startedAt: Date) {
        let elapsedMilliseconds = Date().timeIntervalSince(startedAt) * 1_000
        logger.debug("\(operation, privacy: .public) completed in \(elapsedMilliseconds, format: .fixed(precision: 2), privacy: .public) ms")
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
