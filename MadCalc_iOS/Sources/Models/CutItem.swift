import Foundation

struct CutItem: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var lengthMm: Int
    var quantity: Int

    init(id: UUID = UUID(), lengthMm: Int, quantity: Int) {
        self.id = id
        self.lengthMm = lengthMm
        self.quantity = quantity
    }

    var totalLengthMm: Int {
        lengthMm * quantity
    }
}
