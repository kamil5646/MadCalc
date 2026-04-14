import 'package:flutter_test/flutter_test.dart';
import 'package:madcalc_desktop/models/cut_item.dart';
import 'package:madcalc_desktop/models/cut_settings.dart';
import 'package:madcalc_desktop/services/cut_optimizer.dart';

void main() {
  group('CutOptimizer', () {
    test('matches brute force minimum bar count for small random cases', () {
      final optimizer = CutOptimizer();
      final random = _SeededRandom(0xC0FFEE);

      for (var iteration = 0; iteration < 250; iteration++) {
        final stockLength = random.nextIntInRange(70, 150);
        final sawThickness = random.nextIntInRange(0, 3);
        final pieceCount = random.nextIntInRange(1, 8);
        final cuts = [
          for (var index = 0; index < pieceCount; index++)
            random.nextIntInRange(10, stockLength),
        ];

        final result = optimizer.optimize(
          items: _groupedItems(cuts),
          settings: CutSettings(
            stockLengthMm: stockLength,
            sawThicknessMm: sawThickness,
          ),
        );

        final bruteForceCount = _minimumBarCountByBruteForce(
          cuts: [...cuts]..sort((left, right) => right.compareTo(left)),
          stockLengthMm: stockLength,
          sawThicknessMm: sawThickness,
        );

        expect(
          result.barCount,
          bruteForceCount,
          reason:
              'Mismatch for cuts $cuts, stock $stockLength and saw thickness $sawThickness',
        );
        expect(
          result.bars.every((bar) => bar.usedLengthMm <= stockLength),
          isTrue,
        );
      }
    });

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

    test(
      'finds a better packing than the old greedy case with saw thickness',
      () {
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
      },
    );

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

    test('improves scrap usage when bar count is already minimal', () {
      final optimizer = CutOptimizer();

      final result = optimizer.optimize(
        items: [
          CutItem(id: 'a', lengthMm: 70, quantity: 1),
          CutItem(id: 'b', lengthMm: 60, quantity: 1),
          CutItem(id: 'c', lengthMm: 15, quantity: 1),
          CutItem(id: 'd', lengthMm: 10, quantity: 2),
        ],
        settings: const CutSettings(stockLengthMm: 80, sawThicknessMm: 0),
      );

      expect(result.barCount, 3);
      expect(
        result.bars.map((bar) => bar.cutsMm).toList(),
        equals([
          [70, 10],
          [60, 15],
          [10],
        ]),
      );
      expect(
        result.bars.map((bar) => bar.usedLengthMm).toList(),
        equals([80, 75, 10]),
      );
    });

    test(
      'finishes larger batches quickly instead of hanging on exact search',
      () {
        final optimizer = CutOptimizer();
        final stopwatch = Stopwatch()..start();

        final result = optimizer.optimize(
          items: [
            CutItem(id: 'a', lengthMm: 2350, quantity: 12),
            CutItem(id: 'b', lengthMm: 1820, quantity: 10),
            CutItem(id: 'c', lengthMm: 1270, quantity: 14),
            CutItem(id: 'd', lengthMm: 940, quantity: 18),
            CutItem(id: 'e', lengthMm: 610, quantity: 16),
          ],
          settings: const CutSettings(stockLengthMm: 6000, sawThicknessMm: 3),
        );

        stopwatch.stop();

        expect(result.barCount, greaterThan(0));
        expect(result.bars.every((bar) => bar.usedLengthMm <= 6000), isTrue);
        expect(stopwatch.elapsedMilliseconds, lessThan(2500));
      },
    );
  });
}

List<CutItem> _groupedItems(List<int> cuts) {
  final grouped = <int, int>{};
  for (final cut in cuts) {
    grouped.update(cut, (count) => count + 1, ifAbsent: () => 1);
  }

  final lengths = grouped.keys.toList()
    ..sort((left, right) => right.compareTo(left));
  return [
    for (final length in lengths)
      CutItem(id: 'cut-$length', lengthMm: length, quantity: grouped[length]!),
  ];
}

int _minimumBarCountByBruteForce({
  required List<int> cuts,
  required int stockLengthMm,
  required int sawThicknessMm,
}) {
  var best = cuts.length;
  final usedLengths = <int>[];

  void search(int index) {
    if (usedLengths.length >= best) {
      return;
    }
    if (index == cuts.length) {
      if (usedLengths.length < best) {
        best = usedLengths.length;
      }
      return;
    }

    final cut = cuts[index];
    final triedLoads = <int>{};

    for (var barIndex = 0; barIndex < usedLengths.length; barIndex++) {
      final previousUsed = usedLengths[barIndex];
      if (!triedLoads.add(previousUsed)) {
        continue;
      }

      final nextUsed = previousUsed == 0
          ? cut
          : previousUsed + sawThicknessMm + cut;
      if (nextUsed > stockLengthMm) {
        continue;
      }

      usedLengths[barIndex] = nextUsed;
      search(index + 1);
      usedLengths[barIndex] = previousUsed;
    }

    usedLengths.add(cut);
    search(index + 1);
    usedLengths.removeLast();
  }

  search(0);
  return best;
}

final class _SeededRandom {
  _SeededRandom(this._state);

  int _state;

  int nextIntInRange(int min, int max) {
    _state = (1664525 * _state + 1013904223) & 0x7fffffff;
    final span = max - min + 1;
    return min + (_state % span);
  }
}
