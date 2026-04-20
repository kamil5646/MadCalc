import 'package:flutter_test/flutter_test.dart';
import 'package:madcalc_desktop/models/bar_plan.dart';
import 'package:madcalc_desktop/models/cut_item.dart';
import 'package:madcalc_desktop/models/cut_settings.dart';
import 'package:madcalc_desktop/models/optimization_result.dart';
import 'package:madcalc_desktop/services/cut_optimizer.dart';
import 'package:madcalc_desktop/services/local_ai_plan_generator_service.dart';

void main() {
  group('LocalAiPlanGeneratorService', () {
    test('returns a plan that is never worse than the standard optimizer', () {
      const service = LocalAiPlanGeneratorService();
      final items = [
        CutItem(id: 'a', lengthMm: 2350, quantity: 12),
        CutItem(id: 'b', lengthMm: 1820, quantity: 10),
        CutItem(id: 'c', lengthMm: 1270, quantity: 14),
        CutItem(id: 'd', lengthMm: 940, quantity: 18),
        CutItem(id: 'e', lengthMm: 610, quantity: 16),
      ];
      const settings = CutSettings(stockLengthMm: 6000, sawThicknessMm: 3);

      final generated = service.generate(items: items, settings: settings);
      final standard = CutOptimizer(
        profile: CutOptimizerProfile.standard,
      ).optimize(items: items, settings: settings);

      expect(_isSameOrBetter(generated, standard), isTrue);
      expect(generated.bars.every((bar) => bar.usedLengthMm <= 6000), isTrue);
    });

    test('prefers concentrating waste on fewer bars when fit is the same', () {
      final concentrated = OptimizationResult(
        barCount: 3,
        totalWasteMm: 75,
        utilizationPercent: 75.0,
        bars: [
          _bar(wasteMm: 75, usedLengthMm: 25, cutsMm: [25], barIndex: 1),
          _bar(wasteMm: 0, usedLengthMm: 100, cutsMm: [55, 45], barIndex: 2),
          _bar(
            wasteMm: 0,
            usedLengthMm: 100,
            cutsMm: [55, 25, 20],
            barIndex: 3,
          ),
        ],
      );
      final spread = OptimizationResult(
        barCount: 3,
        totalWasteMm: 75,
        utilizationPercent: 75.0,
        bars: [
          _bar(wasteMm: 30, usedLengthMm: 70, cutsMm: [45, 25], barIndex: 1),
          _bar(wasteMm: 25, usedLengthMm: 75, cutsMm: [55, 20], barIndex: 2),
          _bar(wasteMm: 20, usedLengthMm: 80, cutsMm: [55, 25], barIndex: 3),
        ],
      );

      expect(
        isBetterOptimizationResult(candidate: concentrated, current: spread),
        isTrue,
      );
      expect(
        isBetterOptimizationResult(candidate: spread, current: concentrated),
        isFalse,
      );
    });

    test('background worker returns a valid serialized result', () {
      final payload = <String, dynamic>{
        'items': [
          CutItem(id: 'a', lengthMm: 1200, quantity: 4).toJson(),
          CutItem(id: 'b', lengthMm: 960, quantity: 3).toJson(),
          CutItem(id: 'c', lengthMm: 450, quantity: 5).toJson(),
        ],
        'settings': const CutSettings(
          stockLengthMm: 6000,
          sawThicknessMm: 3,
        ).toJson(),
      };

      final result = OptimizationResult.fromJson(
        optimizeCutsWithLocalAiInBackground(payload),
      );

      expect(result.barCount, greaterThan(0));
      expect(result.totalWasteMm, greaterThanOrEqualTo(0));
      expect(result.bars.every((bar) => bar.usedLengthMm <= 6000), isTrue);
    });
  });
}

bool _isSameOrBetter(
  OptimizationResult candidate,
  OptimizationResult reference,
) {
  return isBetterOptimizationResult(candidate: candidate, current: reference) ||
      (!_isDifferent(candidate, reference));
}

bool _isDifferent(OptimizationResult left, OptimizationResult right) {
  if (left.barCount != right.barCount ||
      left.totalWasteMm != right.totalWasteMm ||
      left.utilizationPercent != right.utilizationPercent ||
      left.bars.length != right.bars.length) {
    return true;
  }
  for (var index = 0; index < left.bars.length; index++) {
    final leftBar = left.bars[index];
    final rightBar = right.bars[index];
    if (leftBar.barIndex != rightBar.barIndex ||
        leftBar.usedLengthMm != rightBar.usedLengthMm ||
        leftBar.wasteMm != rightBar.wasteMm ||
        leftBar.name != rightBar.name ||
        leftBar.cutsMm.join(',') != rightBar.cutsMm.join(',')) {
      return true;
    }
  }
  return false;
}

BarPlan _bar({
  required int barIndex,
  required int usedLengthMm,
  required int wasteMm,
  required List<int> cutsMm,
}) {
  return BarPlan(
    barIndex: barIndex,
    name: '',
    usedLengthMm: usedLengthMm,
    wasteMm: wasteMm,
    cutsMm: cutsMm,
  );
}
