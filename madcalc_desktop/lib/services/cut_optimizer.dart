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

class CutOptimizerProfile {
  const CutOptimizerProfile({
    required this.maxExactUniqueLengths,
    required this.maxExactBarCount,
    required this.maxVisitedStates,
    required this.maxGeneratedPatterns,
    required this.maxLocalRepackCuts,
    required this.maxLocalRepackBarsToInspect,
    required this.smartCandidateLimitSmall,
    required this.smartCandidateLimitLarge,
  });

  static const standard = CutOptimizerProfile(
    maxExactUniqueLengths: 10,
    maxExactBarCount: 12,
    maxVisitedStates: 60000,
    maxGeneratedPatterns: 180000,
    maxLocalRepackCuts: 18,
    maxLocalRepackBarsToInspect: 8,
    smartCandidateLimitSmall: 5,
    smartCandidateLimitLarge: 3,
  );

  static const desktopAi = CutOptimizerProfile(
    maxExactUniqueLengths: 14,
    maxExactBarCount: 16,
    maxVisitedStates: 220000,
    maxGeneratedPatterns: 720000,
    maxLocalRepackCuts: 24,
    maxLocalRepackBarsToInspect: 12,
    smartCandidateLimitSmall: 7,
    smartCandidateLimitLarge: 5,
  );

  final int maxExactUniqueLengths;
  final int maxExactBarCount;
  final int maxVisitedStates;
  final int maxGeneratedPatterns;
  final int maxLocalRepackCuts;
  final int maxLocalRepackBarsToInspect;
  final int smartCandidateLimitSmall;
  final int smartCandidateLimitLarge;
}

class CutOptimizer {
  CutOptimizer({CutOptimizerProfile? profile})
    : _profile = profile ?? CutOptimizerProfile.standard;

  final CutOptimizerProfile _profile;

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
    final exactPacking =
        minimumBarCount < heuristicBars.length &&
            _shouldRunExactSearch(cuts: cuts, heuristicBars: heuristicBars)
        ? _findOptimalPacking(
            cuts: cuts,
            settings: settings,
            lowerBound: minimumBarCount,
            upperBoundBars: heuristicBars,
          )
        : null;

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
    final packedCuts = _improveGreedyPacking(
      cutsByBar: _packCutsGreedy(
        cuts: cuts,
        settings: settings,
        useLookahead: true,
      ),
      settings: settings,
    );
    return _buildBarPlans(cutsByBar: packedCuts, settings: settings);
  }

  List<List<int>> _packCutsGreedy({
    required List<int> cuts,
    required CutSettings settings,
    required bool useLookahead,
  }) {
    final remaining = cuts.toList();
    final bars = <List<int>>[];

    while (remaining.isNotEmpty) {
      final selection = useLookahead
          ? _findSmartCombination(remaining: remaining, settings: settings)
          : _findBestCombination(remaining: remaining, settings: settings);
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

      bars.add(selectedCuts);
    }

    return bars;
  }

  List<List<int>> _improveGreedyPacking({
    required List<List<int>> cutsByBar,
    required CutSettings settings,
  }) {
    var current = _normalizePacking(cutsByBar: cutsByBar, settings: settings);

    while (true) {
      final reduced = _tryReduceBarCount(
        cutsByBar: current,
        settings: settings,
      );
      if (reduced != null) {
        current = _normalizePacking(cutsByBar: reduced, settings: settings);
        continue;
      }

      final locallyRepacked = _tryLocalRepack(
        cutsByBar: current,
        settings: settings,
      );
      if (locallyRepacked != null) {
        current = _normalizePacking(
          cutsByBar: locallyRepacked,
          settings: settings,
        );
        continue;
      }

      final concentrated = _tryConcentrateWaste(
        cutsByBar: current,
        settings: settings,
      );
      if (concentrated == null) {
        return current;
      }
      current = _normalizePacking(cutsByBar: concentrated, settings: settings);
    }
  }

  List<List<int>>? _tryReduceBarCount({
    required List<List<int>> cutsByBar,
    required CutSettings settings,
  }) {
    final sourceIndices = List<int>.generate(cutsByBar.length, (index) => index)
      ..sort((left, right) {
        final leftUsed = _usedLength(cuts: cutsByBar[left], settings: settings);
        final rightUsed = _usedLength(
          cuts: cutsByBar[right],
          settings: settings,
        );
        if (leftUsed != rightUsed) {
          return leftUsed.compareTo(rightUsed);
        }
        return cutsByBar[left].length.compareTo(cutsByBar[right].length);
      });

    for (final sourceIndex in sourceIndices) {
      final redistributed = _tryRedistributeBar(
        cutsByBar: cutsByBar,
        settings: settings,
        sourceIndex: sourceIndex,
      );
      if (redistributed != null) {
        return redistributed;
      }
    }

    return null;
  }

  List<List<int>>? _tryLocalRepack({
    required List<List<int>> cutsByBar,
    required CutSettings settings,
  }) {
    if (cutsByBar.length < 2) {
      return null;
    }

    final candidateIndices =
        List<int>.generate(cutsByBar.length, (index) => index)
          ..sort((left, right) {
            final leftWaste =
                settings.stockLengthMm -
                _usedLength(cuts: cutsByBar[left], settings: settings);
            final rightWaste =
                settings.stockLengthMm -
                _usedLength(cuts: cutsByBar[right], settings: settings);
            if (leftWaste != rightWaste) {
              return rightWaste.compareTo(leftWaste);
            }
            return cutsByBar[left].length.compareTo(cutsByBar[right].length);
          });

    final inspected = candidateIndices
        .take(_profile.maxLocalRepackBarsToInspect)
        .toList(growable: false);

    for (final subsetSize in [4, 3, 2]) {
      if (inspected.length < subsetSize) {
        continue;
      }

      for (final subset in _barIndexCombinations(inspected, subsetSize)) {
        final subsetCuts = <int>[
          for (final index in subset) ...cutsByBar[index],
        ];
        if (subsetCuts.length > _profile.maxLocalRepackCuts) {
          continue;
        }

        final lowerBound = _minimumPossibleBarCount(
          cuts: subsetCuts,
          settings: settings,
        );
        if (lowerBound >= subset.length) {
          continue;
        }

        final upperBoundBars = [
          for (var position = 0; position < subset.length; position++)
            BarPlan(
              barIndex: position + 1,
              name: '',
              cutsMm: [...cutsByBar[subset[position]]],
              usedLengthMm: _usedLength(
                cuts: cutsByBar[subset[position]],
                settings: settings,
              ),
              wasteMm:
                  settings.stockLengthMm -
                  _usedLength(
                    cuts: cutsByBar[subset[position]],
                    settings: settings,
                  ),
            ),
        ];

        final repacked = _findOptimalPacking(
          cuts: [...subsetCuts]..sort((left, right) => right.compareTo(left)),
          settings: settings,
          lowerBound: lowerBound,
          upperBoundBars: upperBoundBars,
        );

        if (repacked == null || repacked.length >= subset.length) {
          continue;
        }

        final remaining = <List<int>>[
          for (var index = 0; index < cutsByBar.length; index++)
            if (!subset.contains(index)) [...cutsByBar[index]],
        ];
        remaining.addAll(repacked);
        return remaining;
      }
    }

    return null;
  }

  List<List<int>>? _tryConcentrateWaste({
    required List<List<int>> cutsByBar,
    required CutSettings settings,
  }) {
    if (cutsByBar.length < 2) {
      return null;
    }

    final currentPacking = _normalizePacking(
      cutsByBar: cutsByBar,
      settings: settings,
    );
    final candidateIndices =
        List<int>.generate(cutsByBar.length, (index) => index)..sort((
          left,
          right,
        ) {
          final leftWaste =
              settings.stockLengthMm -
              _usedLength(cuts: cutsByBar[left], settings: settings);
          final rightWaste =
              settings.stockLengthMm -
              _usedLength(cuts: cutsByBar[right], settings: settings);
          if (leftWaste != rightWaste) {
            return rightWaste.compareTo(leftWaste);
          }
          return _usedLength(
            cuts: cutsByBar[left],
            settings: settings,
          ).compareTo(_usedLength(cuts: cutsByBar[right], settings: settings));
        });

    final inspected = candidateIndices
        .take(_profile.maxLocalRepackBarsToInspect)
        .toList(growable: false);

    for (final subsetSize in [4, 3, 2]) {
      if (inspected.length < subsetSize) {
        continue;
      }

      for (final subset in _barIndexCombinations(inspected, subsetSize)) {
        final subsetCuts = <int>[
          for (final index in subset) ...cutsByBar[index],
        ];
        if (subsetCuts.length > _profile.maxLocalRepackCuts) {
          continue;
        }

        final lowerBound = _minimumPossibleBarCount(
          cuts: subsetCuts,
          settings: settings,
        );
        if (lowerBound > subset.length) {
          continue;
        }

        final upperBoundBars = [
          for (var position = 0; position < subset.length; position++)
            BarPlan(
              barIndex: position + 1,
              name: '',
              cutsMm: [...cutsByBar[subset[position]]],
              usedLengthMm: _usedLength(
                cuts: cutsByBar[subset[position]],
                settings: settings,
              ),
              wasteMm:
                  settings.stockLengthMm -
                  _usedLength(
                    cuts: cutsByBar[subset[position]],
                    settings: settings,
                  ),
            ),
        ];

        final repacked = _findOptimalPacking(
          cuts: [...subsetCuts]..sort((left, right) => right.compareTo(left)),
          settings: settings,
          lowerBound: lowerBound,
          upperBoundBars: upperBoundBars,
          allowSameBarCountImprovement: true,
        );

        if (repacked == null) {
          continue;
        }

        final remaining = <List<int>>[
          for (var index = 0; index < cutsByBar.length; index++)
            if (!subset.contains(index)) [...cutsByBar[index]],
          ...repacked,
        ];
        final normalizedRemaining = _normalizePacking(
          cutsByBar: remaining,
          settings: settings,
        );
        if (_isBetterPacking(
          candidate: normalizedRemaining,
          current: currentPacking,
          settings: settings,
        )) {
          return normalizedRemaining;
        }
      }
    }

    return null;
  }

  Iterable<List<int>> _barIndexCombinations(List<int> indices, int size) sync* {
    final current = <int>[];

    Iterable<List<int>> walk(int startIndex) sync* {
      if (current.length == size) {
        yield List<int>.from(current);
        return;
      }

      for (var index = startIndex; index < indices.length; index++) {
        current.add(indices[index]);
        yield* walk(index + 1);
        current.removeLast();
      }
    }

    yield* walk(0);
  }

  List<List<int>>? _tryRedistributeBar({
    required List<List<int>> cutsByBar,
    required CutSettings settings,
    required int sourceIndex,
  }) {
    final sourceCuts = [...cutsByBar[sourceIndex]]
      ..sort((left, right) => right.compareTo(left));
    if (sourceCuts.isEmpty) {
      return null;
    }

    final targetBars = <List<int>>[];
    final targetUsed = <int>[];
    for (var index = 0; index < cutsByBar.length; index++) {
      if (index == sourceIndex) {
        continue;
      }
      final cuts = [...cutsByBar[index]];
      targetBars.add(cuts);
      targetUsed.add(_usedLength(cuts: cuts, settings: settings));
    }

    bool assign(int cutIndex) {
      if (cutIndex >= sourceCuts.length) {
        return true;
      }

      final cut = sourceCuts[cutIndex];
      final options = <_RedistributionOption>[];
      final seenLoads = <int>{};

      for (
        var targetIndex = 0;
        targetIndex < targetBars.length;
        targetIndex++
      ) {
        final usedBefore = targetUsed[targetIndex];
        if (!seenLoads.add(usedBefore)) {
          continue;
        }

        final usedAfter = usedBefore + settings.sawThicknessMm + cut;
        if (usedAfter > settings.stockLengthMm) {
          continue;
        }

        options.add(
          _RedistributionOption(
            targetIndex: targetIndex,
            remainingCapacity: settings.stockLengthMm - usedAfter,
          ),
        );
      }

      options.sort((left, right) {
        if (left.remainingCapacity != right.remainingCapacity) {
          return left.remainingCapacity.compareTo(right.remainingCapacity);
        }
        return targetBars[left.targetIndex].length.compareTo(
          targetBars[right.targetIndex].length,
        );
      });

      for (final option in options) {
        final targetIndex = option.targetIndex;
        targetBars[targetIndex].add(cut);
        targetUsed[targetIndex] += settings.sawThicknessMm + cut;

        if (assign(cutIndex + 1)) {
          return true;
        }

        targetBars[targetIndex].removeLast();
        targetUsed[targetIndex] -= settings.sawThicknessMm + cut;
      }

      return false;
    }

    if (!assign(0)) {
      return null;
    }

    return [
      for (var index = 0; index < targetBars.length; index++)
        [...targetBars[index]]..sort((left, right) => right.compareTo(left)),
    ];
  }

  _BarSelection _findSmartCombination({
    required List<int> remaining,
    required CutSettings settings,
  }) {
    final candidateLimit = remaining.length <= 12
        ? _profile.smartCandidateLimitSmall
        : _profile.smartCandidateLimitLarge;
    final candidates = _findTopCombinations(
      remaining: remaining,
      settings: settings,
      limit: candidateLimit,
    );

    if (candidates.isEmpty) {
      return const _BarSelection(indices: [], usedLengthMm: 0, wasteMm: 0);
    }
    if (candidates.length == 1 || remaining.length <= 6) {
      return candidates.first;
    }

    _ScoredSelection? best;
    for (final candidate in candidates) {
      final nextRemaining = _removeSelectedCuts(
        remaining: remaining,
        selectedIndices: candidate.indices,
      );
      final completion = _packCutsGreedy(
        cuts: nextRemaining,
        settings: settings,
        useLookahead: false,
      );
      final candidateCuts = [
        for (final index in candidate.indices) remaining[index],
      ];
      final simulatedPacking = _normalizePacking(
        cutsByBar: [candidateCuts, ...completion],
        settings: settings,
      );
      final score = _ScoredSelection(
        selection: candidate,
        packedBars: simulatedPacking,
      );

      if (best == null || _isBetterScoredSelection(score, best, settings)) {
        best = score;
      }
    }

    return best?.selection ?? candidates.first;
  }

  List<List<int>>? _findOptimalPacking({
    required List<int> cuts,
    required CutSettings settings,
    required int lowerBound,
    required List<BarPlan> upperBoundBars,
    bool allowSameBarCountImprovement = false,
  }) {
    final upperBoundBarCount = upperBoundBars.length;
    if (lowerBound > upperBoundBarCount) {
      return null;
    }
    if (!allowSameBarCountImprovement && lowerBound >= upperBoundBarCount) {
      return null;
    }
    final upperBoundPacking = _normalizePacking(
      cutsByBar: [
        for (final bar in upperBoundBars) [...bar.cutsMm],
      ],
      settings: settings,
    );

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

    final currentPatterns = <_BarPattern>[];
    final patternCache = <_PatternState, List<_BarPattern>>{};
    final exactCache = <_ExactSearchState, List<_BarPattern>?>{};
    var visitedStates = 0;
    var generatedPatterns = 0;

    void guardBudget() {
      if (visitedStates > _profile.maxVisitedStates ||
          generatedPatterns > _profile.maxGeneratedPatterns) {
        throw const _SearchBudgetExceeded();
      }
    }

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
        guardBudget();
        if (index == lengths.length) {
          final remainingCapacity = adjustedCapacity - adjustedUsed;
          if (!hasRemainingCutThatFits(
            remainingCounts: state.remainingCounts,
            selectedCounts: selectedCounts,
            remainingCapacity: remainingCapacity,
          )) {
            generatedPatterns++;
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

    List<_BarPattern>? searchExact(_PatternState state, int barsLeft) {
      visitedStates++;
      guardBudget();

      if (!state.remainingCounts.any((count) => count > 0)) {
        return const <_BarPattern>[];
      }
      if (barsLeft == 0) {
        return null;
      }

      final stateLowerBound = lowerBoundFor(state.remainingCounts);
      if (stateLowerBound > barsLeft) {
        return null;
      }

      final cacheKey = _ExactSearchState(
        remainingCounts: state.remainingCounts,
        barsLeft: barsLeft,
      );
      final cached = exactCache[cacheKey];
      if (cached != null || exactCache.containsKey(cacheKey)) {
        return cached;
      }

      for (final pattern in patternsFor(state)) {
        final nextCounts = List<int>.from(state.remainingCounts);
        for (var index = 0; index < nextCounts.length; index++) {
          nextCounts[index] -= pattern.counts[index];
        }

        currentPatterns.add(pattern);
        final completion = searchExact(_PatternState(nextCounts), barsLeft - 1);
        currentPatterns.removeLast();
        if (completion != null) {
          final solution = <_BarPattern>[pattern, ...completion];
          exactCache[cacheKey] = solution;
          return solution;
        }
      }

      exactCache[cacheKey] = null;
      return null;
    }

    try {
      final maxTargetBarCount = allowSameBarCountImprovement
          ? upperBoundBarCount
          : upperBoundBarCount - 1;
      for (
        var targetBarCount = lowerBound;
        targetBarCount <= maxTargetBarCount;
        targetBarCount++
      ) {
        exactCache.clear();
        final solution = searchExact(
          _PatternState(initialCounts),
          targetBarCount,
        );
        if (solution == null) {
          continue;
        }

        final normalizedSolution = _normalizePacking(
          cutsByBar: [for (final pattern in solution) expandPattern(pattern)],
          settings: settings,
        );
        if (targetBarCount < upperBoundBarCount) {
          return normalizedSolution;
        }
        if (_isBetterPacking(
          candidate: normalizedSolution,
          current: upperBoundPacking,
          settings: settings,
        )) {
          return normalizedSolution;
        }
        return null;
      }
    } on _SearchBudgetExceeded {
      // Zwracamy najlepszy dotąd układ albo bezpiecznie spadamy do heurystyki.
    }
    return null;
  }

  bool _shouldRunExactSearch({
    required List<int> cuts,
    required List<BarPlan> heuristicBars,
  }) {
    if (heuristicBars.length > _profile.maxExactBarCount) {
      return false;
    }
    final uniqueLengths = cuts.toSet().length;
    if (uniqueLengths > _profile.maxExactUniqueLengths) {
      return false;
    }
    return true;
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
    final combinations = _findTopCombinations(
      remaining: remaining,
      settings: settings,
      limit: 1,
    );
    return combinations.isEmpty
        ? const _BarSelection(indices: [], usedLengthMm: 0, wasteMm: 0)
        : combinations.first;
  }

  List<_BarSelection> _findTopCombinations({
    required List<int> remaining,
    required CutSettings settings,
    required int limit,
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

    final candidates =
        states.values
            .where((selection) => selection.indices.isNotEmpty)
            .toList(growable: false)
          ..sort(_compareSelections);

    if (candidates.length <= limit) {
      return candidates;
    }
    return candidates.take(limit).toList(growable: false);
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

  int _compareSelections(_BarSelection left, _BarSelection right) {
    if (_isBetter(candidate: left, currentBest: right)) {
      return -1;
    }
    if (_isBetter(candidate: right, currentBest: left)) {
      return 1;
    }
    return 0;
  }

  List<int> _removeSelectedCuts({
    required List<int> remaining,
    required List<int> selectedIndices,
  }) {
    final next = remaining.toList();
    for (final index in selectedIndices.reversed) {
      next.removeAt(index);
    }
    return next;
  }

  bool _isBetterScoredSelection(
    _ScoredSelection candidate,
    _ScoredSelection current,
    CutSettings settings,
  ) {
    if (candidate.packedBars.length != current.packedBars.length) {
      return candidate.packedBars.length < current.packedBars.length;
    }
    if (_isBetterPacking(
      candidate: candidate.packedBars,
      current: current.packedBars,
      settings: settings,
    )) {
      return true;
    }
    return _isBetter(
      candidate: candidate.selection,
      currentBest: current.selection,
    );
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

class _ScoredSelection {
  const _ScoredSelection({required this.selection, required this.packedBars});

  final _BarSelection selection;
  final List<List<int>> packedBars;
}

class _RedistributionOption {
  const _RedistributionOption({
    required this.targetIndex,
    required this.remainingCapacity,
  });

  final int targetIndex;
  final int remainingCapacity;
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

class _ExactSearchState {
  const _ExactSearchState({
    required this.remainingCounts,
    required this.barsLeft,
  });

  final List<int> remainingCounts;
  final int barsLeft;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! _ExactSearchState ||
        other.barsLeft != barsLeft ||
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
  int get hashCode => Object.hash(barsLeft, Object.hashAll(remainingCounts));
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

class _SearchBudgetExceeded implements Exception {
  const _SearchBudgetExceeded();
}
