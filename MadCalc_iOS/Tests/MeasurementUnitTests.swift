import XCTest
@testable import MadCalc

final class MeasurementUnitTests: XCTestCase {
    func testParsesCentimetersWithComma() {
        XCTAssertEqual(MeasurementUnit.centimeters.parse("0,3"), 3)
        XCTAssertEqual(MeasurementUnit.centimeters.parse("600"), 6000)
    }

    func testFormatsCentimetersAndMillimetersLikeOtherPlatforms() {
        XCTAssertEqual(MeasurementUnit.centimeters.format(6000), "600 cm")
        XCTAssertEqual(MeasurementUnit.centimeters.format(1234), "123,4 cm")
        XCTAssertEqual(MeasurementUnit.millimeters.format(1234), "1234 mm")
    }

    func testBarPlanDisplayNameFallsBackToNumberedBar() {
        let unnamedBar = BarPlan(
            barIndex: 4,
            name: "   ",
            cutsMm: [1200, 800],
            usedLengthMm: 2003,
            wasteMm: 3997
        )

        XCTAssertEqual(unnamedBar.displayName, "Sztanga 4")
    }
}
