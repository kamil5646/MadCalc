import 'package:flutter_test/flutter_test.dart';
import 'package:madcalc_desktop/models/bar_plan.dart';
import 'package:madcalc_desktop/models/cut_item.dart';
import 'package:madcalc_desktop/models/cut_settings.dart';
import 'package:madcalc_desktop/models/measurement_unit.dart';
import 'package:madcalc_desktop/models/optimization_result.dart';
import 'package:madcalc_desktop/services/local_ai_analysis_service.dart';

void main() {
  group('LocalAiAnalysisService', () {
    test('flags repeated strong patterns in a good plan', () {
      final service = LocalAiAnalysisService();

      final analysis = service.analyze(
        items: [
          CutItem(id: 'a', lengthMm: 1200, quantity: 4),
          CutItem(id: 'b', lengthMm: 960, quantity: 4),
        ],
        settings: const CutSettings(stockLengthMm: 2200, sawThicknessMm: 3),
        result: OptimizationResult(
          barCount: 4,
          totalWasteMm: 148,
          utilizationPercent: 98.3,
          bars: [
            BarPlan(
              barIndex: 1,
              name: '',
              cutsMm: [1200, 960],
              usedLengthMm: 2163,
              wasteMm: 37,
            ),
            BarPlan(
              barIndex: 2,
              name: '',
              cutsMm: [1200, 960],
              usedLengthMm: 2163,
              wasteMm: 37,
            ),
            BarPlan(
              barIndex: 3,
              name: '',
              cutsMm: [1200, 960],
              usedLengthMm: 2163,
              wasteMm: 37,
            ),
            BarPlan(
              barIndex: 4,
              name: '',
              cutsMm: [1200, 960],
              usedLengthMm: 2163,
              wasteMm: 37,
            ),
          ],
        ),
        unit: MeasurementUnit.centimeters,
      );

      expect(analysis.score, greaterThanOrEqualTo(95));
      expect(
        analysis.highlights.any((line) => line.contains('Powtarza się układ')),
        isTrue,
      );
      expect(analysis.warnings, isEmpty);
    });

    test('warns when the plan leaves a single poorly used bar', () {
      final service = LocalAiAnalysisService();

      final analysis = service.analyze(
        items: [
          CutItem(id: 'a', lengthMm: 84, quantity: 1),
          CutItem(id: 'b', lengthMm: 54, quantity: 1),
          CutItem(id: 'c', lengthMm: 53, quantity: 1),
          CutItem(id: 'd', lengthMm: 52, quantity: 1),
          CutItem(id: 'e', lengthMm: 42, quantity: 1),
          CutItem(id: 'f', lengthMm: 39, quantity: 1),
          CutItem(id: 'g', lengthMm: 27, quantity: 1),
          CutItem(id: 'h', lengthMm: 18, quantity: 1),
          CutItem(id: 'i', lengthMm: 10, quantity: 1),
          CutItem(id: 'j', lengthMm: 6, quantity: 1),
        ],
        settings: const CutSettings(stockLengthMm: 100, sawThicknessMm: 1),
        result: OptimizationResult(
          barCount: 5,
          totalWasteMm: 110,
          utilizationPercent: 78.0,
          bars: [
            BarPlan(
              barIndex: 1,
              name: '',
              cutsMm: [54, 27, 10, 6],
              usedLengthMm: 100,
              wasteMm: 0,
            ),
            BarPlan(
              barIndex: 2,
              name: '',
              cutsMm: [53, 42],
              usedLengthMm: 96,
              wasteMm: 4,
            ),
            BarPlan(
              barIndex: 3,
              name: '',
              cutsMm: [52, 39],
              usedLengthMm: 92,
              wasteMm: 8,
            ),
            BarPlan(
              barIndex: 4,
              name: '',
              cutsMm: [84],
              usedLengthMm: 84,
              wasteMm: 16,
            ),
            BarPlan(
              barIndex: 5,
              name: '',
              cutsMm: [18],
              usedLengthMm: 18,
              wasteMm: 82,
            ),
          ],
        ),
        unit: MeasurementUnit.centimeters,
      );

      expect(analysis.score, lessThan(80));
      expect(
        analysis.warnings.any((line) => line.contains('tylko 1 element')),
        isTrue,
      );
      expect(
        analysis.warnings.any((line) => line.contains('odpad większy')),
        isTrue,
      );
      expect(analysis.suggestions, isNotEmpty);
    });
  });
}
