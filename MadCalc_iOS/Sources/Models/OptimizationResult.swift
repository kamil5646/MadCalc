import Foundation

struct OptimizationResult: Codable, Equatable, Sendable {
    var barCount: Int
    var totalWasteMm: Int
    var utilizationPercent: Double
    var bars: [BarPlan]
}
