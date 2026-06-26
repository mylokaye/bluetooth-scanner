import Foundation

struct BluetoothAppearance: Codable, Identifiable, Hashable, Sendable {
    let appearanceId: Int
    let appearanceIdHex: String
    let category: String
    let subcategory: String?
    let description: String

    var id: Int { appearanceId }
}
