import XCTest
@testable import MadCalc

final class CutOptimizerTests: XCTestCase {
    func testMatchesBruteForceMinimumBarCountForSmallRandomCases() throws {
        let optimizer = CutOptimizer()
        var generator = SeededGenerator(seed: 0xC0FFEE)

        for _ in 0..<250 {
            let stockLength = Int.random(in: 70...150, using: &generator)
            let sawThickness = Int.random(in: 0...3, using: &generator)
            let pieceCount = Int.random(in: 1...8, using: &generator)
            let cuts = (0..<pieceCount).map { _ in
                Int.random(in: 10...stockLength, using: &generator)
            }

            let items = groupedItems(from: cuts)
            let result = try optimizer.optimize(
                items: items,
                settings: CutSettings(stockLengthMm: stockLength, sawThicknessMm: sawThickness)
            )

            let bruteForceCount = minimumBarCountByBruteForce(
                cuts: cuts.sorted(by: >),
                stockLengthMm: stockLength,
                sawThicknessMm: sawThickness
            )

            XCTAssertEqual(
                result.barCount,
                bruteForceCount,
                "Niezgodność dla cięć \(cuts), sztangi \(stockLength) i grubości piły \(sawThickness)"
            )
            XCTAssertTrue(result.bars.allSatisfy { $0.usedLengthMm <= stockLength })
        }
    }

    func testFindsBetterPackingThanOldGreedyCaseWithoutSawThickness() throws {
        let optimizer = CutOptimizer()

        let result = try optimizer.optimize(
            items: [
                CutItem(lengthMm: 70, quantity: 2),
                CutItem(lengthMm: 60, quantity: 1),
                CutItem(lengthMm: 20, quantity: 1),
                CutItem(lengthMm: 10, quantity: 2)
            ],
            settings: CutSettings(stockLengthMm: 80, sawThicknessMm: 0)
        )

        XCTAssertEqual(result.barCount, 3)
        XCTAssertEqual(
            result.bars.map(\.cutsMm),
            [
                [70, 10],
                [70, 10],
                [60, 20]
            ]
        )
    }

    func testFindsBetterPackingThanOldGreedyCaseWithSawThickness() throws {
        let optimizer = CutOptimizer()

        let result = try optimizer.optimize(
            items: [
                CutItem(lengthMm: 70, quantity: 2),
                CutItem(lengthMm: 60, quantity: 1),
                CutItem(lengthMm: 25, quantity: 1),
                CutItem(lengthMm: 15, quantity: 1),
                CutItem(lengthMm: 10, quantity: 1)
            ],
            settings: CutSettings(stockLengthMm: 90, sawThicknessMm: 1)
        )

        XCTAssertEqual(result.barCount, 3)
        XCTAssertTrue(result.bars.allSatisfy { $0.usedLengthMm <= 90 })
    }

    func testStaysDeterministicForSameInput() throws {
        let optimizer = CutOptimizer()
        let items = [
            CutItem(lengthMm: 1200, quantity: 4),
            CutItem(lengthMm: 960, quantity: 3),
            CutItem(lengthMm: 450, quantity: 5)
        ]
        let settings = CutSettings(stockLengthMm: 6000, sawThicknessMm: 3)

        let first = try optimizer.optimize(items: items, settings: settings)
        let second = try optimizer.optimize(items: items, settings: settings)

        XCTAssertEqual(second.barCount, first.barCount)
        XCTAssertEqual(second.bars.map(\.cutsMm), first.bars.map(\.cutsMm))
    }

    private func groupedItems(from cuts: [Int]) -> [CutItem] {
        let grouped = Dictionary(grouping: cuts, by: { $0 })
        return grouped
            .sorted(by: { $0.key > $1.key })
            .map { length, values in
                CutItem(lengthMm: length, quantity: values.count)
            }
    }

    private func minimumBarCountByBruteForce(
        cuts: [Int],
        stockLengthMm: Int,
        sawThicknessMm: Int
    ) -> Int {
        var best = cuts.count
        var usedLengths: [Int] = []

        func search(_ index: Int) {
            if usedLengths.count >= best {
                return
            }
            if index == cuts.count {
                best = min(best, usedLengths.count)
                return
            }

            let cut = cuts[index]
            var triedLoads: Set<Int> = []

            for barIndex in usedLengths.indices {
                let previousUsed = usedLengths[barIndex]
                guard triedLoads.insert(previousUsed).inserted else {
                    continue
                }

                let nextUsed = previousUsed == 0
                    ? cut
                    : previousUsed + sawThicknessMm + cut
                guard nextUsed <= stockLengthMm else {
                    continue
                }

                usedLengths[barIndex] = nextUsed
                search(index + 1)
                usedLengths[barIndex] = previousUsed
            }

            usedLengths.append(cut)
            search(index + 1)
            usedLengths.removeLast()
        }

        search(0)
        return best
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state = 6364136223846793005 &* state &+ 1442695040888963407
        return state
    }
}
