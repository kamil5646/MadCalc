import Foundation

struct OptimizationResult: Codable, Equatable {
    var barCount: Int
    var totalWasteMm: Int
    var utilizationPercent: Double
    var bars: [BarPlan]
}
