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

    final remaining = _expandAndSort(items).toList();
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

      final cuts = selection.indices.map((index) => remaining[index]).toList();
      for (final index in selection.indices.reversed) {
        remaining.removeAt(index);
      }

      bars.add(
        BarPlan(
          barIndex: bars.length + 1,
          name: '',
          cutsMm: cuts,
          usedLengthMm: selection.usedLengthMm,
          wasteMm: selection.wasteMm,
        ),
      );
    }

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
