import XCTest
@testable import MadCalc

final class CutOptimizerTests: XCTestCase {
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
}
