import '../models/bar_plan.dart';
import '../models/cut_item.dart';
import '../models/cut_settings.dart';
import '../models/optimization_result.dart';

class CutOptimizationException implements Exception {
  CutOptimizationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class CutOptimizer {
  OptimizationResult optimize({
    required List<CutItem> items,
    required CutSettings settings,
  }) {
    _validateInput(items: items, settings: settings);

    final cuts = _expandAndSort(items);
    final heuristicBars = _buildGreedyBars(cuts: cuts, settings: settings);
    final minimumBarCount = _minimumPossibleBarCount(
      cuts: cuts,
      settings: settings,
    );
    final exactPacking = _findOptimalPacking(
      cuts: cuts,
      settings: settings,
      lowerBound: minimumBarCount,
      upperBoundBars: heuristicBars,
    );

    final bars = exactPacking != null
        ? _buildBarPlans(cutsByBar: exactPacking, settings: settings)
        : heuristicBars;

    final totalWasteMm = bars.fold<int>(0, (sum, bar) => sum + bar.wasteMm);
    final totalStockMm = bars.length * settings.stockLengthMm;
    final totalUsedMm = totalStockMm - totalWasteMm;
    final utilizationPercent = totalStockMm == 0
        ? 0.0
        : (totalUsedMm / totalStockMm) * 100;

    return OptimizationResult(
      barCount: bars.length,
      totalWasteMm: totalWasteMm,
      utilizationPercent: utilizationPercent,
      bars: bars,
    );
  }

  void _validateInput({
    required List<CutItem> items,
    required CutSettings settings,
  }) {
    if (items.isEmpty) {
      throw CutOptimizationException(
        'Dodaj przynajmniej jeden element do cięcia.',
      );
    }
    if (settings.stockLengthMm <= 0) {
      throw CutOptimizationException(
        'Długość sztangi musi być większa od zera.',
      );
    }
    if (settings.sawThicknessMm < 0) {
      throw CutOptimizationException('Grubość piły nie może być ujemna.');
    }

    for (final item in items) {
      if (item.lengthMm <= 0) {
        throw CutOptimizationException(
          'Każda długość elementu musi być większa od zera.',
        );
      }
      if (item.quantity <= 0) {
        throw CutOptimizationException('Ilość sztuk musi być większa od zera.');
      }
      if (item.lengthMm > settings.stockLengthMm) {
        throw CutOptimizationException(
          'Element ${item.lengthMm} mm jest dłuższy niż sztanga ${settings.stockLengthMm} mm.',
        );
      }
    }
  }

  List<int> _expandAndSort(List<CutItem> items) {
    final expanded = <int>[];
    for (final item in items) {
      expanded.addAll(List<int>.filled(item.quantity, item.lengthMm));
    }
    expanded.sort((left, right) => right.compareTo(left));
    return expanded;
  }

  int _minimumPossibleBarCount({
    required List<int> cuts,
    required CutSettings settings,
  }) {
    final adjustedCapacity = settings.stockLengthMm + settings.sawThicknessMm;
    final totalAdjustedLength =
        cuts.fold<int>(0, (sum, cut) => sum + cut) +
        (settings.sawThicknessMm * cuts.length);
    final minimumBarCount =
        (totalAdjustedLength + adjustedCapacity - 1) ~/ adjustedCapacity;
    return minimumBarCount < 1 ? 1 : minimumBarCount;
  }

  List<BarPlan> _buildGreedyBars({
    required List<int> cuts,
    required CutSettings settings,
  }) {
    final remaining = cuts.toList();
    final bars = <BarPlan>[];

    while (remaining.isNotEmpty) {
      final selection = _findBestCombination(
        remaining: remaining,
        settings: settings,
      );
      if (selection.indices.isEmpty) {
        throw CutOptimizationException(
          'Nie udało się ułożyć planu cięcia dla podanych danych.',
        );
      }

      final selectedCuts = selection.indices
          .map((index) => remaining[index])
          .toList();
      for (final index in selection.indices.reversed) {
        remaining.removeAt(index);
      }

      bars.add(
        BarPlan(
          barIndex: bars.length + 1,
          name: '',
          cutsMm: selectedCuts,
          usedLengthMm: selection.usedLengthMm,
          wasteMm: selection.wasteMm,
        ),
      );
    }

    return bars;
  }

  List<List<int>>? _findOptimalPacking({
    required List<int> cuts,
    required CutSettings settings,
    required int lowerBound,
    required List<BarPlan> upperBoundBars,
  }) {
    final adjustedCapacity = settings.stockLengthMm + settings.sawThicknessMm;
    final groupedCuts = <int, int>{};
    for (final cut in cuts) {
      groupedCuts.update(cut, (count) => count + 1, ifAbsent: () => 1);
    }
    final lengths = groupedCuts.keys.toList()
      ..sort((left, right) => right.compareTo(left));
    final initialCounts = [for (final length in lengths) groupedCuts[length]!];
    final adjustedWeights = [
      for (final length in lengths) length + settings.sawThicknessMm,
    ];

    final initialPacking = _normalizePacking(
      cutsByBar: [
        for (final bar in upperBoundBars)
          [...bar.cutsMm]..sort((left, right) => right.compareTo(left)),
      ],
      settings: settings,
    );
    var bestBarCount = upperBoundBars.length;
    var bestPacking = initialPacking;

    final currentPatterns = <_BarPattern>[];
    final patternCache = <_PatternState, List<_BarPattern>>{};
    final bestBarsUsedForState = <_PatternState, int>{};

    int lowerBoundFor(List<int> counts) {
      var remainingAdjustedWeight = 0;
      for (var index = 0; index < counts.length; index++) {
        remainingAdjustedWeight += counts[index] * adjustedWeights[index];
      }
      if (remainingAdjustedWeight == 0) {
        return 0;
      }
      return (remainingAdjustedWeight + adjustedCapacity - 1) ~/
          adjustedCapacity;
    }

    List<int> expandPattern(_BarPattern pattern) {
      final bar = <int>[];
      for (var index = 0; index < pattern.counts.length; index++) {
        bar.addAll(List<int>.filled(pattern.counts[index], lengths[index]));
      }
      return bar;
    }

    bool hasRemainingCutThatFits({
      required List<int> remainingCounts,
      required List<int> selectedCounts,
      required int remainingCapacity,
    }) {
      for (var index = 0; index < remainingCounts.length; index++) {
        if (remainingCounts[index] > selectedCounts[index] &&
            adjustedWeights[index] <= remainingCapacity) {
          return true;
        }
      }
      return false;
    }

    bool isBetterPattern({
      required _BarPattern candidate,
      required _BarPattern current,
    }) {
      if (candidate.adjustedUsed != current.adjustedUsed) {
        return candidate.adjustedUsed > current.adjustedUsed;
      }

      for (var index = 0; index < candidate.counts.length; index++) {
        if (candidate.counts[index] != current.counts[index]) {
          return candidate.counts[index] > current.counts[index];
        }
      }

      return false;
    }

    List<_BarPattern> patternsFor(_PatternState state) {
      final cached = patternCache[state];
      if (cached != null) {
        return cached;
      }

      final anchorIndex = state.remainingCounts.indexWhere(
        (count) => count > 0,
      );
      if (anchorIndex == -1) {
        return const [];
      }

      final selectedCounts = List<int>.filled(lengths.length, 0);
      selectedCounts[anchorIndex] = 1;
      final generated = <_BarPattern>[];

      void buildPattern(int index, int adjustedUsed) {
        if (index == lengths.length) {
          final remainingCapacity = adjustedCapacity - adjustedUsed;
          if (!hasRemainingCutThatFits(
            remainingCounts: state.remainingCounts,
            selectedCounts: selectedCounts,
            remainingCapacity: remainingCapacity,
          )) {
            generated.add(
              _BarPattern(
                counts: List<int>.from(selectedCounts),
                adjustedUsed: adjustedUsed,
              ),
            );
          }
          return;
        }

        final available = state.remainingCounts[index] - selectedCounts[index];
        final maxTake =
            available <
                ((adjustedCapacity - adjustedUsed) ~/ adjustedWeights[index])
            ? available
            : ((adjustedCapacity - adjustedUsed) ~/ adjustedWeights[index]);

        for (var take = maxTake; take >= 0; take--) {
          selectedCounts[index] += take;
          buildPattern(
            index + 1,
            adjustedUsed + (take * adjustedWeights[index]),
          );
          selectedCounts[index] -= take;
        }
      }

      buildPattern(anchorIndex, adjustedWeights[anchorIndex]);
      generated.sort((left, right) {
        if (isBetterPattern(candidate: left, current: right)) {
          return -1;
        }
        if (isBetterPattern(candidate: right, current: left)) {
          return 1;
        }
        return 0;
      });
      patternCache[state] = generated;
      return generated;
    }

    void search(_PatternState state, int barsUsed) {
      if (barsUsed > bestBarCount) {
        return;
      }

      if (!state.remainingCounts.any((count) => count > 0)) {
        final candidatePacking = _normalizePacking(
          cutsByBar: [
            for (final pattern in currentPatterns) expandPattern(pattern),
          ],
          settings: settings,
        );
        if (barsUsed < bestBarCount ||
            _isBetterPacking(
              candidate: candidatePacking,
              current: bestPacking,
              settings: settings,
            )) {
          bestBarCount = barsUsed;
          bestPacking = candidatePacking;
        }
        return;
      }

      final stateLowerBound = lowerBoundFor(state.remainingCounts);
      if (barsUsed + stateLowerBound > bestBarCount) {
        return;
      }

      final bestSeen = bestBarsUsedForState[state];
      if (bestSeen != null && bestSeen < barsUsed) {
        return;
      }
      if (bestSeen == null || barsUsed < bestSeen) {
        bestBarsUsedForState[state] = barsUsed;
      }

      for (final pattern in patternsFor(state)) {
        final nextCounts = List<int>.from(state.remainingCounts);
        for (var index = 0; index < nextCounts.length; index++) {
          nextCounts[index] -= pattern.counts[index];
        }

        currentPatterns.add(pattern);
        search(_PatternState(nextCounts), barsUsed + 1);
        currentPatterns.removeLast();
      }
    }

    search(_PatternState(initialCounts), 0);
    if (bestBarCount < upperBoundBars.length ||
        _isBetterPacking(
          candidate: bestPacking,
          current: initialPacking,
          settings: settings,
        )) {
      return bestPacking;
    }
    return null;
  }

  List<BarPlan> _buildBarPlans({
    required List<List<int>> cutsByBar,
    required CutSettings settings,
  }) {
    final sortedBars = _normalizePacking(
      cutsByBar: cutsByBar,
      settings: settings,
    );

    return [
      for (var index = 0; index < sortedBars.length; index++)
        BarPlan(
          barIndex: index + 1,
          name: '',
          cutsMm: sortedBars[index],
          usedLengthMm: _usedLength(
            cuts: sortedBars[index],
            settings: settings,
          ),
          wasteMm:
              settings.stockLengthMm -
              _usedLength(cuts: sortedBars[index], settings: settings),
        ),
    ];
  }

  List<List<int>> _normalizePacking({
    required List<List<int>> cutsByBar,
    required CutSettings settings,
  }) {
    final sortedBars =
        cutsByBar
            .map(
              (cuts) => [...cuts]..sort((left, right) => right.compareTo(left)),
            )
            .toList()
          ..sort(
            (left, right) =>
                _compareBars(left: left, right: right, settings: settings),
          );
    return sortedBars;
  }

  int _compareBars({
    required List<int> left,
    required List<int> right,
    required CutSettings settings,
  }) {
    final leftUsed = _usedLength(cuts: left, settings: settings);
    final rightUsed = _usedLength(cuts: right, settings: settings);
    if (leftUsed != rightUsed) {
      return rightUsed.compareTo(leftUsed);
    }
    for (var index = 0; index < left.length && index < right.length; index++) {
      if (left[index] != right[index]) {
        return right[index].compareTo(left[index]);
      }
    }
    return left.length.compareTo(right.length);
  }

  bool _isBetterPacking({
    required List<List<int>> candidate,
    required List<List<int>> current,
    required CutSettings settings,
  }) {
    if (candidate.length != current.length) {
      return candidate.length < current.length;
    }

    final sharedLength = candidate.length < current.length
        ? candidate.length
        : current.length;
    for (var index = 0; index < sharedLength; index++) {
      final comparison = _compareBars(
        left: candidate[index],
        right: current[index],
        settings: settings,
      );
      if (comparison != 0) {
        return comparison < 0;
      }
    }

    return false;
  }

  int _usedLength({required List<int> cuts, required CutSettings settings}) {
    return cuts.fold<int>(0, (sum, cut) => sum + cut) +
        (settings.sawThicknessMm * (cuts.isNotEmpty ? cuts.length - 1 : 0));
  }

  _BarSelection _findBestCombination({
    required List<int> remaining,
    required CutSettings settings,
  }) {
    final adjustedCapacity = settings.stockLengthMm + settings.sawThicknessMm;
    var states = <int, _BarSelection>{
      0: const _BarSelection(indices: [], usedLengthMm: 0, wasteMm: 0),
    };

    for (var index = 0; index < remaining.length; index++) {
      final cutLengthMm = remaining[index];
      final adjustedWeight = cutLengthMm + settings.sawThicknessMm;
      final nextStates = Map<int, _BarSelection>.from(states);

      for (final entry in states.entries) {
        final nextAdjustedLength = entry.key + adjustedWeight;
        if (nextAdjustedLength > adjustedCapacity) {
          continue;
        }

        final indices = [...entry.value.indices, index];
        final totalCutsMm = indices.fold<int>(
          0,
          (sum, cutIndex) => sum + remaining[cutIndex],
        );
        final cutCount = indices.length;
        final usedLengthMm =
            totalCutsMm +
            settings.sawThicknessMm * (cutCount > 0 ? cutCount - 1 : 0);
        final candidate = _BarSelection(
          indices: indices,
          usedLengthMm: usedLengthMm,
          wasteMm: settings.stockLengthMm - usedLengthMm,
        );

        if (_isBetter(
          candidate: candidate,
          currentBest: nextStates[nextAdjustedLength],
        )) {
          nextStates[nextAdjustedLength] = candidate;
        }
      }

      states = nextStates;
    }

    var best = const _BarSelection(indices: [], usedLengthMm: 0, wasteMm: 0);
    for (final candidate in states.values.where(
      (selection) => selection.indices.isNotEmpty,
    )) {
      if (best.indices.isEmpty ||
          _isBetter(candidate: candidate, currentBest: best)) {
        best = candidate;
      }
    }
    return best;
  }

  bool _isBetter({
    required _BarSelection candidate,
    required _BarSelection? currentBest,
  }) {
    if (currentBest == null) {
      return true;
    }
    if (candidate.wasteMm != currentBest.wasteMm) {
      return candidate.wasteMm < currentBest.wasteMm;
    }
    if (candidate.indices.length != currentBest.indices.length) {
      return candidate.indices.length > currentBest.indices.length;
    }

    for (var index = 0; index < candidate.indices.length; index++) {
      final left = candidate.indices[index];
      final right = currentBest.indices[index];
      if (left != right) {
        return left < right;
      }
    }

    return false;
  }
}

class _BarSelection {
  const _BarSelection({
    required this.indices,
    required this.usedLengthMm,
    required this.wasteMm,
  });

  final List<int> indices;
  final int usedLengthMm;
  final int wasteMm;
}

class _PatternState {
  const _PatternState(this.remainingCounts);

  final List<int> remainingCounts;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! _PatternState ||
        other.remainingCounts.length != remainingCounts.length) {
      return false;
    }
    for (var index = 0; index < remainingCounts.length; index++) {
      if (other.remainingCounts[index] != remainingCounts[index]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(remainingCounts);
}

class _BarPattern {
  const _BarPattern({required this.counts, required this.adjustedUsed});

  final List<int> counts;
  final int adjustedUsed;
}

Map<String, dynamic> optimizeCutsInBackground(Map<String, dynamic> payload) {
  final items = (payload['items'] as List<dynamic>)
      .map((item) => CutItem.fromJson(Map<String, dynamic>.from(item as Map)))
      .toList();
  final settings = CutSettings.fromJson(
    Map<String, dynamic>.from(payload['settings'] as Map),
  );
  final optimizer = CutOptimizer();
  return optimizer.optimize(items: items, settings: settings).toJson();
}
