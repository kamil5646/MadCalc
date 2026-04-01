import Foundation

struct CutOptimizationError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

struct CutOptimizer {
    func optimize(items: [CutItem], settings: CutSettings) throws -> OptimizationResult {
        try validateInput(items: items, settings: settings)

        var remaining = expandAndSort(items)
        var bars: [BarPlan] = []

        while !remaining.isEmpty {
            let selection = findBestCombination(remaining: remaining, settings: settings)
            guard !selection.indices.isEmpty else {
                throw CutOptimizationError(message: "Nie udało się ułożyć planu cięcia dla podanych danych.")
            }

            let cuts = selection.indices.map { remaining[$0] }
            for index in selection.indices.reversed() {
                remaining.remove(at: index)
            }

            bars.append(
                BarPlan(
                    barIndex: bars.count + 1,
                    name: "",
                    cutsMm: cuts,
                    usedLengthMm: selection.usedLengthMm,
                    wasteMm: selection.wasteMm
                )
            )
        }

        let totalWasteMm = bars.reduce(0) { $0 + $1.wasteMm }
        let totalStockMm = bars.count * settings.stockLengthMm
        let totalUsedMm = totalStockMm - totalWasteMm
        let utilizationPercent = totalStockMm == 0 ? 0 : (Double(totalUsedMm) / Double(totalStockMm)) * 100

        return OptimizationResult(
            barCount: bars.count,
            totalWasteMm: totalWasteMm,
            utilizationPercent: utilizationPercent,
            bars: bars
        )
    }

    private func validateInput(items: [CutItem], settings: CutSettings) throws {
        guard !items.isEmpty else {
            throw CutOptimizationError(message: "Dodaj przynajmniej jeden element do cięcia.")
        }
        guard settings.stockLengthMm > 0 else {
            throw CutOptimizationError(message: "Długość sztangi musi być większa od zera.")
        }
        guard settings.sawThicknessMm >= 0 else {
            throw CutOptimizationError(message: "Grubość piły nie może być ujemna.")
        }

        for item in items {
            guard item.lengthMm > 0 else {
                throw CutOptimizationError(message: "Każda długość elementu musi być większa od zera.")
            }
            guard item.quantity > 0 else {
                throw CutOptimizationError(message: "Ilość sztuk musi być większa od zera.")
            }
            guard item.lengthMm <= settings.stockLengthMm else {
                throw CutOptimizationError(
                    message: "Element \(item.lengthMm) mm jest dłuższy niż sztanga \(settings.stockLengthMm) mm."
                )
            }
        }
    }

    private func expandAndSort(_ items: [CutItem]) -> [Int] {
        var expanded: [Int] = []
        for item in items {
            expanded.append(contentsOf: Array(repeating: item.lengthMm, count: item.quantity))
        }
        return expanded.sorted(by: >)
    }

    private func findBestCombination(remaining: [Int], settings: CutSettings) -> BarSelection {
        let adjustedCapacity = settings.stockLengthMm + settings.sawThicknessMm
        var states: [Int: BarSelection] = [0: BarSelection(indices: [], usedLengthMm: 0, wasteMm: 0)]

        for index in remaining.indices {
            let cutLengthMm = remaining[index]
            let adjustedWeight = cutLengthMm + settings.sawThicknessMm
            var nextStates = states

            for (adjustedLength, current) in states {
                let nextAdjustedLength = adjustedLength + adjustedWeight
                guard nextAdjustedLength <= adjustedCapacity else {
                    continue
                }

                let indices = current.indices + [index]
                let totalCutsMm = indices.reduce(0) { $0 + remaining[$1] }
                let cutCount = indices.count
                let usedLengthMm = totalCutsMm + settings.sawThicknessMm * max(0, cutCount - 1)
                let candidate = BarSelection(
                    indices: indices,
                    usedLengthMm: usedLengthMm,
                    wasteMm: settings.stockLengthMm - usedLengthMm
                )

                if isBetter(candidate: candidate, than: nextStates[nextAdjustedLength]) {
                    nextStates[nextAdjustedLength] = candidate
                }
            }

            states = nextStates
        }

        return states.values
            .filter { !$0.indices.isEmpty }
            .reduce(BarSelection(indices: [], usedLengthMm: 0, wasteMm: 0)) { best, candidate in
                best.indices.isEmpty || isBetter(candidate: candidate, than: best) ? candidate : best
            }
    }

    private func isBetter(candidate: BarSelection, than currentBest: BarSelection?) -> Bool {
        guard let currentBest else { return true }
        if candidate.wasteMm != currentBest.wasteMm {
            return candidate.wasteMm < currentBest.wasteMm
        }
        if candidate.indices.count != currentBest.indices.count {
            return candidate.indices.count > currentBest.indices.count
        }
        return false
    }
}

private struct BarSelection {
    let indices: [Int]
    let usedLengthMm: Int
    let wasteMm: Int
}
