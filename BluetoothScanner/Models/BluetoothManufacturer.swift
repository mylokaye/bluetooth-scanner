import Foundation

struct BluetoothManufacturer: Codable, Identifiable, Hashable {
    let companyId: Int
    let companyIdHex: String
    let manufacturer: String

    var id: Int { companyId }
}
