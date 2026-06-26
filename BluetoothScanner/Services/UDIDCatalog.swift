import Foundation

struct UDIDCatalogEntry: Hashable {
    let company: String
    let uuid: String
    let category: String
}

final class UDIDCatalog {
    static let empty = UDIDCatalog(entriesByUUID: [:])

    private let entriesByUUID: [String: UDIDCatalogEntry]

    init(entriesByUUID: [String: UDIDCatalogEntry]) {
        self.entriesByUUID = entriesByUUID
    }

    convenience init(csvURL: URL) throws {
        let csv = try String(contentsOf: csvURL, encoding: .utf8)
        self.init(entriesByUUID: Self.parse(csv: csv))
    }

    func entry(for serviceUUIDs: [String]) -> UDIDCatalogEntry? {
        serviceUUIDs.lazy
            .compactMap(Self.normalize(uuid:))
            .compactMap { self.entriesByUUID[$0] }
            .first
    }

    private static func parse(csv: String) -> [String: UDIDCatalogEntry] {
        var result: [String: UDIDCatalogEntry] = [:]
        let rows = CatalogCSV.parseRows(csv)

        for row in rows.dropFirst() where row.count >= 3 {
            let company = row[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let category = row[2].trimmingCharacters(in: .whitespacesAndNewlines)
            let uuidValues = row[1]
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

            for uuidValue in uuidValues {
                guard let uuid = normalize(uuid: uuidValue) else { continue }
                result[uuid] = UDIDCatalogEntry(company: company, uuid: uuid, category: category)
            }
        }

        return result
    }
}

final class ManufacturerIdentifierCatalog {
    static let empty = ManufacturerIdentifierCatalog(manufacturersByIdentifier: [:])

    private let manufacturersByIdentifier: [String: String]

    init(manufacturersByIdentifier: [String: String]) {
        self.manufacturersByIdentifier = manufacturersByIdentifier
    }

    convenience init(csvURL: URL) throws {
        let csv = try String(contentsOf: csvURL, encoding: .utf8)
        self.init(manufacturersByIdentifier: Self.parse(csv: csv))
    }

    func manufacturerName(for identifier: String?) -> String? {
        guard let identifier else { return nil }
        return CatalogCSV.identifierLookupKeys(identifier)
            .lazy
            .compactMap { self.manufacturersByIdentifier[$0] }
            .first
    }

    private static func parse(csv: String) -> [String: String] {
        var result: [String: String] = [:]
        let rows = CatalogCSV.parseRows(csv)

        for row in rows.dropFirst() where row.count >= 2 {
            let company = row[0].trimmingCharacters(in: .whitespacesAndNewlines)
            for identifierValue in row[1].split(separator: ",") {
                for key in CatalogCSV.identifierLookupKeys(String(identifierValue)) {
                    result[key] = company
                }
            }
        }

        return result
    }
}

final class AppearanceCatalog {
    static let empty = AppearanceCatalog(namesByValue: [:])

    private let namesByValue: [Int: [String]]

    init(namesByValue: [Int: [String]]) {
        self.namesByValue = namesByValue
    }

    convenience init(csvURL: URL) throws {
        let csv = try String(contentsOf: csvURL, encoding: .utf8)
        self.init(namesByValue: Self.parse(csv: csv))
    }

    func appearanceName(for value: Int?) -> String? {
        guard let value else { return nil }

        if let exactName = preferredName(from: namesByValue[value]) {
            return exactName
        }

        let categoryValue = value >> 6
        if let categoryName = preferredName(from: namesByValue[categoryValue]) {
            return categoryName
        }

        return nil
    }

    private func preferredName(from names: [String]?) -> String? {
        names?
            .filter { $0.lowercased() != "unknown" }
            .first
    }

    private static func parse(csv: String) -> [Int: [String]] {
        var result: [Int: [String]] = [:]
        let rows = CatalogCSV.parseRows(csv)

        for row in rows.dropFirst() where row.count >= 2 {
            let name = row[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let value = CatalogCSV.integerValue(row[1]) else { continue }
            result[value, default: []].append(name)
        }

        return result
    }
}

enum CatalogCSV {
    static func identifierLookupKeys(_ value: String) -> [String] {
        guard let normalized = normalizeIdentifier(value) else { return [] }
        var keys = [normalized]

        if let integerValue = Int(normalized, radix: 16) {
            keys.append(String(integerValue, radix: 16).uppercased())
            keys.append(String(format: "%04X", integerValue))
            keys.append(String(integerValue))
        }

        return Array(Set(keys))
    }

    static func normalizeIdentifier(_ uuid: String) -> String? {
        let trimmed = uuid
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "0X", with: "")

        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }

    static func integerValue(_ value: String) -> Int? {
        guard let normalized = normalizeIdentifier(value) else { return nil }
        return Int(normalized, radix: 16) ?? Int(normalized)
    }

    static func parseRows(_ csv: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var isInsideQuotes = false
        var index = csv.startIndex

        while index < csv.endIndex {
            let character = csv[index]

            if character == "\"" {
                let nextIndex = csv.index(after: index)
                if isInsideQuotes, nextIndex < csv.endIndex, csv[nextIndex] == "\"" {
                    field.append(character)
                    index = nextIndex
                } else {
                    isInsideQuotes.toggle()
                }
            } else if character == ",", !isInsideQuotes {
                row.append(clean(field))
                field = ""
            } else if character == "\n", !isInsideQuotes {
                row.append(clean(field))
                field = ""
                if !row.allSatisfy(\.isEmpty) {
                    rows.append(row)
                }
                row = []
            } else if character != "\r" {
                field.append(character)
            }

            index = csv.index(after: index)
        }

        row.append(clean(field))
        if !row.allSatisfy(\.isEmpty) {
            rows.append(row)
        }

        return rows
    }

    private static func clean(_ field: String) -> String {
        field
            .trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension UDIDCatalog {
    static func normalize(uuid: String) -> String? {
        CatalogCSV.normalizeIdentifier(uuid)
    }
}
