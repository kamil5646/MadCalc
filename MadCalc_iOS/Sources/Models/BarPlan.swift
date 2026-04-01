import Foundation

struct BarPlan: Codable, Equatable, Identifiable {
    var barIndex: Int
    var name: String
    var cutsMm: [Int]
    var usedLengthMm: Int
    var wasteMm: Int

    var id: Int { barIndex }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Sztanga \(barIndex)" : trimmed
    }

    var cutCount: Int {
        cutsMm.count
    }

    var totalCutsLengthMm: Int {
        cutsMm.reduce(0, +)
    }
}
