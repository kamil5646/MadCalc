import 'package:flutter_test/flutter_test.dart';
import 'package:madcalc_desktop/models/bar_plan.dart';
import 'package:madcalc_desktop/models/cut_item.dart';
import 'package:madcalc_desktop/models/cut_settings.dart';
import 'package:madcalc_desktop/models/measurement_unit.dart';
import 'package:madcalc_desktop/models/optimization_result.dart';
import 'package:madcalc_desktop/services/pdf_report_builder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PdfReportBuilder', () {
    test('builds a long report without hitting a low page cap', () async {
      final builder = PdfReportBuilder();
      final fonts = await PdfFontAssets.load();

      final result = OptimizationResult(
        barCount: 260,
        totalWasteMm: 260000,
        utilizationPercent: 82.4,
        bars: [
          for (var index = 0; index < 260; index++)
            BarPlan(
              barIndex: index + 1,
              name:
                  'Sztanga produkcyjna ${index + 1} z dluzsza nazwa do testu raportu PDF',
              cutsMm: const [1200, 1200, 900, 900, 750, 600],
              usedLengthMm: 5565,
              wasteMm: 435,
            ),
        ],
      );

      final data = await builder.build(
        items: [
          CutItem(id: 'a', lengthMm: 1200, quantity: 200),
          CutItem(id: 'b', lengthMm: 900, quantity: 180),
          CutItem(id: 'c', lengthMm: 750, quantity: 120),
          CutItem(id: 'd', lengthMm: 600, quantity: 90),
        ],
        settings: const CutSettings(stockLengthMm: 6000, sawThicknessMm: 3),
        result: result,
        unit: MeasurementUnit.centimeters,
        generatedAt: DateTime(2026, 4, 1, 12, 0),
        regularFontBytes: fonts.regularBytes,
        boldFontBytes: fonts.boldBytes,
      );

      expect(data.length, greaterThan(1024));
    });
  });
}
