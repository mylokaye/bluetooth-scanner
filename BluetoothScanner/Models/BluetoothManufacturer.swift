import Foundation

struct BluetoothManufacturer: Codable, Identifiable, Hashable, Sendable {
    let companyId: Int
    let companyIdHex: String
    let manufacturer: String

    var id: Int { companyId }
}
