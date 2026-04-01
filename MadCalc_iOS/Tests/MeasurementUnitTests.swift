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

  func testPDFExportCompletesForVeryLongBarNames() {
    let expectation = expectation(description: "PDF export finishes")

    Task { @MainActor in
      do {
        let items = [
          CutItem(lengthMm: 1200, quantity: 2),
          CutItem(lengthMm: 900, quantity: 2),
        ]
        let settings = CutSettings(stockLengthMm: 6000, sawThicknessMm: 3)
        let result = OptimizationResult(
          barCount: 1,
          totalWasteMm: 2994,
          utilizationPercent: 50.1,
          bars: [
            BarPlan(
              barIndex: 1,
              name: Array(
                repeating: "Bardzo dluga nazwa sztangi testowej do sprawdzenia paginacji PDF",
                count: 80
              ).joined(separator: " "),
              cutsMm: [1200, 1200, 900, 900],
              usedLengthMm: 3006,
              wasteMm: 2994
            )
          ]
        )

        let url = try PDFReportBuilder().makeTemporaryReportURL(
          items: items,
          settings: settings,
          result: result,
          unit: .centimeters,
          generatedAt: Date()
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertGreaterThan(attributes[.size] as? Int64 ?? 0, 0)
      } catch {
        XCTFail("Eksport PDF nie powinien zawieść: \(error)")
      }

      expectation.fulfill()
    }

    wait(for: [expectation], timeout: 5)
  }
}
