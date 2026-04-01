import Foundation

struct CutOptimizationError: LocalizedError, Sendable {
    let message: String

    var errorDescription: String? { message }
}

struct CutOptimizer: Sendable {
    private let exactSearchNodeLimit = 250_000

    func optimize(items: [CutItem], settings: CutSettings) throws -> OptimizationResult {
        try validateInput(items: items, settings: settings)

        let cuts = expandAndSort(items)
        let heuristicBars = try buildGreedyBars(cuts: cuts, settings: settings)
        let minimumBarCount = minimumPossibleBarCount(for: cuts, settings: settings)

        let bars: [BarPlan]
        if heuristicBars.count > minimumBarCount,
           let exactPacking = findExactPacking(
               cuts: cuts,
               settings: settings,
               startingBarCount: minimumBarCount,
               maximumBarCount: heuristicBars.count - 1
           ) {
            bars = buildBarPlans(from: exactPacking, settings: settings)
        } else {
            bars = heuristicBars
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

    private func minimumPossibleBarCount(for cuts: [Int], settings: CutSettings) -> Int {
        let adjustedCapacity = settings.stockLengthMm + settings.sawThicknessMm
        let totalAdjustedLength = cuts.reduce(0, +) + (settings.sawThicknessMm * cuts.count)
        return max(1, (totalAdjustedLength + adjustedCapacity - 1) / adjustedCapacity)
    }

    private func buildGreedyBars(cuts: [Int], settings: CutSettings) throws -> [BarPlan] {
        var remaining = cuts
        var bars: [BarPlan] = []

        while !remaining.isEmpty {
            let selection = findBestCombination(remaining: remaining, settings: settings)
            guard !selection.indices.isEmpty else {
                throw CutOptimizationError(message: "Nie udało się ułożyć planu cięcia dla podanych danych.")
            }

            let selectedCuts = selection.indices.map { remaining[$0] }
            for index in selection.indices.reversed() {
                remaining.remove(at: index)
            }

            bars.append(
                BarPlan(
                    barIndex: bars.count + 1,
                    name: "",
                    cutsMm: selectedCuts,
                    usedLengthMm: selection.usedLengthMm,
                    wasteMm: selection.wasteMm
                )
            )
        }

        return bars
    }

    private func findExactPacking(
        cuts: [Int],
        settings: CutSettings,
        startingBarCount: Int,
        maximumBarCount: Int
    ) -> [[Int]]? {
        guard startingBarCount <= maximumBarCount else {
            return nil
        }

        for barCount in startingBarCount...maximumBarCount {
            if let packing = searchFeasiblePacking(cuts: cuts, settings: settings, barCount: barCount) {
                return packing
            }
        }

        return nil
    }

    private func searchFeasiblePacking(cuts: [Int], settings: CutSettings, barCount: Int) -> [[Int]]? {
        let adjustedCapacity = settings.stockLengthMm + settings.sawThicknessMm
        let adjustedWeights = cuts.map { $0 + settings.sawThicknessMm }
        let totalAdjustedLength = adjustedWeights.reduce(0, +)

        guard totalAdjustedLength <= barCount * adjustedCapacity else {
            return nil
        }

        var suffixAdjustedWeights = Array(repeating: 0, count: cuts.count + 1)
        for index in stride(from: cuts.count - 1, through: 0, by: -1) {
            suffixAdjustedWeights[index] = suffixAdjustedWeights[index + 1] + adjustedWeights[index]
        }

        var bars = Array(repeating: SearchBar(), count: barCount)
        var visitedNodes = 0
        var aborted = false
        var failedStates: Set<SearchState> = []

        func dfs(_ cutIndex: Int) -> Bool {
            if cutIndex == cuts.count {
                return true
            }

            if visitedNodes >= exactSearchNodeLimit {
                aborted = true
                return false
            }
            visitedNodes += 1

            let remainingCapacity = (barCount * adjustedCapacity) - bars.reduce(0) { $0 + $1.adjustedUsed }
            guard suffixAdjustedWeights[cutIndex] <= remainingCapacity else {
                return false
            }

            let state = SearchState(index: cutIndex, adjustedLoads: bars.map(\.adjustedUsed).sorted())
            guard !failedStates.contains(state) else {
                return false
            }

            let cut = cuts[cutIndex]
            let adjustedWeight = adjustedWeights[cutIndex]

            let candidateIndices = bars.indices
                .filter { bars[$0].adjustedUsed + adjustedWeight <= adjustedCapacity }
                .sorted { left, right in
                    let leftRemaining = adjustedCapacity - (bars[left].adjustedUsed + adjustedWeight)
                    let rightRemaining = adjustedCapacity - (bars[right].adjustedUsed + adjustedWeight)
                    if leftRemaining != rightRemaining {
                        return leftRemaining < rightRemaining
                    }
                    if bars[left].adjustedUsed != bars[right].adjustedUsed {
                        return bars[left].adjustedUsed > bars[right].adjustedUsed
                    }
                    return left < right
                }

            var triedLoads: Set<Int> = []

            for index in candidateIndices {
                let previousLoad = bars[index].adjustedUsed
                guard !triedLoads.contains(previousLoad) else {
                    continue
                }
                triedLoads.insert(previousLoad)

                bars[index].cuts.append(cut)
                bars[index].adjustedUsed += adjustedWeight

                if dfs(cutIndex + 1) {
                    return true
                }

                bars[index].cuts.removeLast()
                bars[index].adjustedUsed -= adjustedWeight

                if aborted {
                    return false
                }

                if previousLoad == 0 {
                    break
                }
            }

            if !aborted {
                failedStates.insert(state)
            }

            return false
        }

        guard dfs(0), !aborted else {
            return nil
        }

        return bars
            .filter { !$0.cuts.isEmpty }
            .map { $0.cuts.sorted(by: >) }
    }

    private func buildBarPlans(from bars: [[Int]], settings: CutSettings) -> [BarPlan] {
        let sortedBars = bars
            .map { $0.sorted(by: >) }
            .sorted(by: { left, right in
                let leftUsed = usedLength(for: left, settings: settings)
                let rightUsed = usedLength(for: right, settings: settings)

                if leftUsed != rightUsed {
                    return leftUsed > rightUsed
                }
                if left.count != right.count {
                    return left.count > right.count
                }
                return compareCuts(left, right)
            })

        return sortedBars.enumerated().map { offset, cuts in
            let usedLengthMm = usedLength(for: cuts, settings: settings)
            return BarPlan(
                barIndex: offset + 1,
                name: "",
                cutsMm: cuts,
                usedLengthMm: usedLengthMm,
                wasteMm: settings.stockLengthMm - usedLengthMm
            )
        }
    }

    private func usedLength(for cuts: [Int], settings: CutSettings) -> Int {
        cuts.reduce(0, +) + (settings.sawThicknessMm * max(0, cuts.count - 1))
    }

    private func compareCuts(_ left: [Int], _ right: [Int]) -> Bool {
        for (leftCut, rightCut) in zip(left, right) where leftCut != rightCut {
            return leftCut > rightCut
        }
        return left.count >= right.count
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

private struct SearchBar {
    var cuts: [Int] = []
    var adjustedUsed = 0
}

private struct SearchState: Hashable {
    let index: Int
    let adjustedLoads: [Int]
}
