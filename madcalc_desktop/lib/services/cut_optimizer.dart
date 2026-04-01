import 'package:flutter/foundation.dart' show listEquals;

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
  static const int _exactSearchNodeLimit = 250000;

  OptimizationResult optimize({
    required List<CutItem> items,
    required CutSettings settings,
  }) {
    _validateInput(items: items, settings: settings);

    final cuts = _expandAndSort(items);
    final heuristicBars = _buildGreedyBars(cuts: cuts, settings: settings);
    final minimumBarCount = _minimumPossibleBarCount(cuts: cuts, settings: settings);
    final exactPacking = heuristicBars.length > minimumBarCount
        ? _findExactPacking(
            cuts: cuts,
            settings: settings,
            startingBarCount: minimumBarCount,
            maximumBarCount: heuristicBars.length - 1,
          )
        : null;

    final bars =
        exactPacking != null ? _buildBarPlans(cutsByBar: exactPacking, settings: settings) : heuristicBars;

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
      throw CutOptimizationException('Dodaj przynajmniej jeden element do cięcia.');
    }
    if (settings.stockLengthMm <= 0) {
      throw CutOptimizationException('Długość sztangi musi być większa od zera.');
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
        throw CutOptimizationException(
          'Ilość sztuk musi być większa od zera.',
        );
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
        cuts.fold<int>(0, (sum, cut) => sum + cut) + (settings.sawThicknessMm * cuts.length);
    final minimumBarCount = (totalAdjustedLength + adjustedCapacity - 1) ~/ adjustedCapacity;
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

      final selectedCuts = selection.indices.map((index) => remaining[index]).toList();
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

  List<List<int>>? _findExactPacking({
    required List<int> cuts,
    required CutSettings settings,
    required int startingBarCount,
    required int maximumBarCount,
  }) {
    if (startingBarCount > maximumBarCount) {
      return null;
    }

    for (var barCount = startingBarCount; barCount <= maximumBarCount; barCount++) {
      final packing = _searchFeasiblePacking(
        cuts: cuts,
        settings: settings,
        barCount: barCount,
      );
      if (packing != null) {
        return packing;
      }
    }

    return null;
  }

  List<List<int>>? _searchFeasiblePacking({
    required List<int> cuts,
    required CutSettings settings,
    required int barCount,
  }) {
    final adjustedCapacity = settings.stockLengthMm + settings.sawThicknessMm;
    final adjustedWeights = cuts.map((cut) => cut + settings.sawThicknessMm).toList();
    final totalAdjustedLength = adjustedWeights.fold<int>(0, (sum, value) => sum + value);
    if (totalAdjustedLength > barCount * adjustedCapacity) {
      return null;
    }

    final suffixAdjustedWeights = List<int>.filled(cuts.length + 1, 0);
    for (var index = cuts.length - 1; index >= 0; index--) {
      suffixAdjustedWeights[index] = suffixAdjustedWeights[index + 1] + adjustedWeights[index];
    }

    final bars = List<_SearchBar>.generate(barCount, (_) => _SearchBar());
    final failedStates = <_SearchState>{};
    var visitedNodes = 0;
    var aborted = false;

    bool dfs(int cutIndex) {
      if (cutIndex == cuts.length) {
        return true;
      }

      if (visitedNodes >= _exactSearchNodeLimit) {
        aborted = true;
        return false;
      }
      visitedNodes++;

      final remainingCapacity = (barCount * adjustedCapacity) -
          bars.fold<int>(0, (sum, bar) => sum + bar.adjustedUsed);
      if (suffixAdjustedWeights[cutIndex] > remainingCapacity) {
        return false;
      }

      final state = _SearchState(
        cutIndex,
        (bars.map((bar) => bar.adjustedUsed).toList()..sort()),
      );
      if (failedStates.contains(state)) {
        return false;
      }

      final cut = cuts[cutIndex];
      final adjustedWeight = adjustedWeights[cutIndex];
      final candidateIndices = bars.asMap().entries
          .where((entry) => entry.value.adjustedUsed + adjustedWeight <= adjustedCapacity)
          .map((entry) => entry.key)
          .toList()
        ..sort((left, right) {
          final leftRemaining = adjustedCapacity - (bars[left].adjustedUsed + adjustedWeight);
          final rightRemaining = adjustedCapacity - (bars[right].adjustedUsed + adjustedWeight);
          if (leftRemaining != rightRemaining) {
            return leftRemaining.compareTo(rightRemaining);
          }
          if (bars[left].adjustedUsed != bars[right].adjustedUsed) {
            return bars[right].adjustedUsed.compareTo(bars[left].adjustedUsed);
          }
          return left.compareTo(right);
        });

      final triedLoads = <int>{};

      for (final index in candidateIndices) {
        final previousLoad = bars[index].adjustedUsed;
        if (!triedLoads.add(previousLoad)) {
          continue;
        }

        bars[index].cuts.add(cut);
        bars[index].adjustedUsed += adjustedWeight;

        if (dfs(cutIndex + 1)) {
          return true;
        }

        bars[index].cuts.removeLast();
        bars[index].adjustedUsed -= adjustedWeight;

        if (aborted) {
          return false;
        }
        if (previousLoad == 0) {
          break;
        }
      }

      if (!aborted) {
        failedStates.add(state);
      }

      return false;
    }

    if (!dfs(0) || aborted) {
      return null;
    }

    return bars
        .where((bar) => bar.cuts.isNotEmpty)
        .map((bar) => [...bar.cuts]..sort((left, right) => right.compareTo(left)))
        .toList();
  }

  List<BarPlan> _buildBarPlans({
    required List<List<int>> cutsByBar,
    required CutSettings settings,
  }) {
    final sortedBars = cutsByBar
        .map((cuts) => [...cuts]..sort((left, right) => right.compareTo(left)))
        .toList()
      ..sort((left, right) {
        final leftUsed = _usedLength(cuts: left, settings: settings);
        final rightUsed = _usedLength(cuts: right, settings: settings);
        if (leftUsed != rightUsed) {
          return rightUsed.compareTo(leftUsed);
        }
        if (left.length != right.length) {
          return right.length.compareTo(left.length);
        }
        for (var index = 0; index < left.length && index < right.length; index++) {
          if (left[index] != right[index]) {
            return right[index].compareTo(left[index]);
          }
        }
        return right.length.compareTo(left.length);
      });

    return [
      for (var index = 0; index < sortedBars.length; index++)
        BarPlan(
          barIndex: index + 1,
          name: '',
          cutsMm: sortedBars[index],
          usedLengthMm: _usedLength(cuts: sortedBars[index], settings: settings),
          wasteMm: settings.stockLengthMm -
              _usedLength(cuts: sortedBars[index], settings: settings),
        ),
    ];
  }

  int _usedLength({
    required List<int> cuts,
    required CutSettings settings,
  }) {
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
            totalCutsMm + settings.sawThicknessMm * (cutCount > 0 ? cutCount - 1 : 0);
        final candidate = _BarSelection(
          indices: indices,
          usedLengthMm: usedLengthMm,
          wasteMm: settings.stockLengthMm - usedLengthMm,
        );

        if (_isBetter(candidate: candidate, currentBest: nextStates[nextAdjustedLength])) {
          nextStates[nextAdjustedLength] = candidate;
        }
      }

      states = nextStates;
    }

    var best = const _BarSelection(indices: [], usedLengthMm: 0, wasteMm: 0);
    for (final candidate in states.values.where((selection) => selection.indices.isNotEmpty)) {
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

class _SearchBar {
  final List<int> cuts = <int>[];
  int adjustedUsed = 0;
}

class _SearchState {
  const _SearchState(this.index, this.adjustedLoads);

  final int index;
  final List<int> adjustedLoads;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is _SearchState &&
        other.index == index &&
        listEquals(other.adjustedLoads, adjustedLoads);
  }

  @override
  int get hashCode => Object.hash(index, Object.hashAll(adjustedLoads));
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
