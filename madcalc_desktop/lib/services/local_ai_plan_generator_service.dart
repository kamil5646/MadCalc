import '../models/cut_item.dart';
import '../models/cut_settings.dart';
import '../models/optimization_result.dart';
import 'cut_optimizer.dart';

class LocalAiPlanGeneratorService {
  const LocalAiPlanGeneratorService();

  OptimizationResult generate({
    required List<CutItem> items,
    required CutSettings settings,
  }) {
    final standardResult = CutOptimizer(
      profile: CutOptimizerProfile.standard,
    ).optimize(items: items, settings: settings);

    var bestResult = standardResult;

    try {
      final desktopAiResult = CutOptimizer(
        profile: CutOptimizerProfile.desktopAi,
      ).optimize(items: items, settings: settings);

      if (isBetterOptimizationResult(
        candidate: desktopAiResult,
        current: bestResult,
      )) {
        bestResult = desktopAiResult;
      }
    } on CutOptimizationException {
      rethrow;
    } catch (_) {
      // Wariant desktopowy jest próbą poprawy wyniku, ale podstawowy plan
      // musi pozostać stabilnym fallbackiem nawet przy większych partiach.
    }

    return bestResult;
  }
}

bool isBetterOptimizationResult({
  required OptimizationResult candidate,
  required OptimizationResult current,
}) {
  if (candidate.barCount != current.barCount) {
    return candidate.barCount < current.barCount;
  }
  if (candidate.totalWasteMm != current.totalWasteMm) {
    return candidate.totalWasteMm < current.totalWasteMm;
  }

  final candidateWasteSpread = _wasteSpreadSignature(candidate);
  final currentWasteSpread = _wasteSpreadSignature(current);
  final sharedLength = candidateWasteSpread.length < currentWasteSpread.length
      ? candidateWasteSpread.length
      : currentWasteSpread.length;
  for (var index = 0; index < sharedLength; index++) {
    if (candidateWasteSpread[index] != currentWasteSpread[index]) {
      return candidateWasteSpread[index] > currentWasteSpread[index];
    }
  }

  final utilizationComparison = candidate.utilizationPercent.compareTo(
    current.utilizationPercent,
  );
  if (utilizationComparison != 0) {
    return utilizationComparison > 0;
  }

  return _signature(candidate).compareTo(_signature(current)) < 0;
}

List<int> _wasteSpreadSignature(OptimizationResult result) {
  final wastes = result.bars.map((bar) => bar.wasteMm).toList(growable: false)
    ..sort((left, right) => right.compareTo(left));
  return wastes;
}

String _signature(OptimizationResult result) {
  return result.bars
      .map(
        (bar) => '${bar.usedLengthMm}:${bar.wasteMm}:${bar.cutsMm.join(",")}',
      )
      .join('|');
}

Map<String, dynamic> optimizeCutsWithLocalAiInBackground(
  Map<String, dynamic> payload,
) {
  final items = (payload['items'] as List<dynamic>)
      .map((item) => CutItem.fromJson(Map<String, dynamic>.from(item as Map)))
      .toList(growable: false);
  final settings = CutSettings.fromJson(
    Map<String, dynamic>.from(payload['settings'] as Map),
  );
  final generator = LocalAiPlanGeneratorService();
  return generator.generate(items: items, settings: settings).toJson();
}
