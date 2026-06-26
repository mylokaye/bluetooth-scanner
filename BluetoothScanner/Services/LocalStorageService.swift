import Foundation

struct LocalStorageService {
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
    }

    func load() async throws -> AppDataSnapshot {
        let fileURL = fileURL

        return try await Task.detached(priority: .utility) {
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return .empty
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let data = try Data(contentsOf: fileURL)
            return try decoder.decode(AppDataSnapshot.self, from: data)
        }.value
    }

    func save(_ snapshot: AppDataSnapshot) async throws {
        let fileURL = fileURL

        try await Task.detached(priority: .utility) {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601

            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: [.atomic])
        }.value
    }

    private static func defaultFileURL() -> URL {
        let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return supportDirectory
            .appendingPathComponent("BluetoothScanner", isDirectory: true)
            .appendingPathComponent("observations.json")
    }
}
