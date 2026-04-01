import 'package:flutter_test/flutter_test.dart';
import 'package:madcalc_desktop/models/cut_item.dart';
import 'package:madcalc_desktop/models/cut_settings.dart';
import 'package:madcalc_desktop/services/cut_optimizer.dart';

void main() {
  group('CutOptimizer', () {
    test('finds a better packing than the old greedy case without kerf', () {
      final optimizer = CutOptimizer();

      final result = optimizer.optimize(
        items: [
          CutItem(id: 'a', lengthMm: 70, quantity: 2),
          CutItem(id: 'b', lengthMm: 60, quantity: 1),
          CutItem(id: 'c', lengthMm: 20, quantity: 1),
          CutItem(id: 'd', lengthMm: 10, quantity: 2),
        ],
        settings: const CutSettings(stockLengthMm: 80, sawThicknessMm: 0),
      );

      expect(result.barCount, 3);
      expect(
        result.bars.map((bar) => bar.cutsMm).toList(),
        equals([
          [70, 10],
          [70, 10],
          [60, 20],
        ]),
      );
    });

    test('finds a better packing than the old greedy case with saw thickness', () {
      final optimizer = CutOptimizer();

      final result = optimizer.optimize(
        items: [
          CutItem(id: 'a', lengthMm: 70, quantity: 2),
          CutItem(id: 'b', lengthMm: 60, quantity: 1),
          CutItem(id: 'c', lengthMm: 25, quantity: 1),
          CutItem(id: 'd', lengthMm: 15, quantity: 1),
          CutItem(id: 'e', lengthMm: 10, quantity: 1),
        ],
        settings: const CutSettings(stockLengthMm: 90, sawThicknessMm: 1),
      );

      expect(result.barCount, 3);
      for (final bar in result.bars) {
        expect(bar.usedLengthMm <= 90, isTrue);
      }
    });

    test('stays deterministic for the same input', () {
      final optimizer = CutOptimizer();
      final items = [
        CutItem(id: 'a', lengthMm: 1200, quantity: 4),
        CutItem(id: 'b', lengthMm: 960, quantity: 3),
        CutItem(id: 'c', lengthMm: 450, quantity: 5),
      ];
      const settings = CutSettings(stockLengthMm: 6000, sawThicknessMm: 3);

      final first = optimizer.optimize(items: items, settings: settings);
      final second = optimizer.optimize(items: items, settings: settings);

      expect(second.barCount, first.barCount);
      expect(
        second.bars.map((bar) => bar.cutsMm).toList(),
        equals(first.bars.map((bar) => bar.cutsMm).toList()),
      );
    });
  });
}
