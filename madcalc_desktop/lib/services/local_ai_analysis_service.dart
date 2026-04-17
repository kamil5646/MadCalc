import '../models/bar_plan.dart';
import '../models/cut_item.dart';
import '../models/cut_settings.dart';
import '../models/local_ai_analysis.dart';
import '../models/measurement_unit.dart';
import '../models/optimization_result.dart';

class LocalAiAnalysisService {
  LocalAiAnalysis analyze({
    required List<CutItem> items,
    required CutSettings settings,
    required OptimizationResult result,
    required MeasurementUnit unit,
  }) {
    final stockLengthMm = settings.stockLengthMm;
    final totalPieces = items.fold<int>(0, (sum, item) => sum + item.quantity);
    final totalSawLossMm = result.bars.fold<int>(
      0,
      (sum, bar) =>
          sum +
          ((bar.cutCount - 1).clamp(0, bar.cutCount) * settings.sawThicknessMm),
    );
    final wasteThresholdMm = (stockLengthMm * 0.15).round();
    final largeWasteThresholdMm = (stockLengthMm * 0.25).round();

    final worstBars = [...result.bars]
      ..sort((left, right) => right.wasteMm.compareTo(left.wasteMm));
    final highWasteBars = worstBars
        .where((bar) => bar.wasteMm >= wasteThresholdMm)
        .toList(growable: false);
    final veryHighWasteBars = worstBars
        .where((bar) => bar.wasteMm >= largeWasteThresholdMm)
        .toList(growable: false);
    final singleCutBars = result.bars
        .where((bar) => bar.cutCount <= 1)
        .toList(growable: false);
    final lowFillBars = result.bars
        .where((bar) => bar.usedLengthMm <= (stockLengthMm * 0.70).round())
        .toList(growable: false);
    final repeatedPatterns = _findRepeatedPatterns(result.bars);

    var score = result.utilizationPercent.round();
    if (highWasteBars.length >= 2) {
      score -= 4;
    }
    if (veryHighWasteBars.isNotEmpty) {
      score -= 6;
    }
    if (singleCutBars.isNotEmpty) {
      score -= 6;
    }
    if (lowFillBars.length >= 2) {
      score -= 3;
    }
    if (repeatedPatterns.isNotEmpty) {
      score += 2;
    }
    if (result.utilizationPercent >= 97) {
      score += 2;
    }
    score = score.clamp(0, 100);

    final statusLabel = _statusLabel(score);
    final highlights = <String>[];
    final warnings = <String>[];
    final suggestions = <String>[];

    if (result.utilizationPercent >= 95) {
      highlights.add(
        'Wykorzystanie materiału jest bardzo wysokie: ${_formatPercent(result.utilizationPercent)}%.',
      );
    } else if (result.utilizationPercent >= 88) {
      highlights.add(
        'Plan trzyma solidny poziom wykorzystania materiału: ${_formatPercent(result.utilizationPercent)}%.',
      );
    }

    if (repeatedPatterns.isNotEmpty) {
      final strongestPattern = repeatedPatterns.first;
      highlights.add(
        'Powtarza się układ ${_formatPattern(strongestPattern.exampleBar, unit)} '
        'na ${strongestPattern.count} ${_pluralize('sztandze', 'sztangach', strongestPattern.count)}, '
        'co ułatwia produkcję seryjną.',
      );
    }

    final almostFullBars = result.bars
        .where((bar) => bar.wasteMm <= (stockLengthMm * 0.05).round())
        .length;
    if (almostFullBars > 0) {
      highlights.add(
        '$almostFullBars ${_pluralize('sztanga jest', 'sztangi są', almostFullBars)} '
        'domknięte bardzo ciasno, z odpadem do ${unit.format((stockLengthMm * 0.05).round())}.',
      );
    }

    if (highWasteBars.isNotEmpty) {
      final worstBar = highWasteBars.first;
      warnings.add(
        '${highWasteBars.length} ${_pluralize('sztanga ma', 'sztangi mają', highWasteBars.length)} '
        'odpad większy niż 15% długości bazowej. Najsłabsza to sztanga ${worstBar.barIndex}: '
        '${unit.format(worstBar.wasteMm)} odpadu.',
      );
    }

    if (singleCutBars.isNotEmpty) {
      warnings.add(
        '${singleCutBars.length} ${_pluralize('sztanga zawiera', 'sztangi zawierają', singleCutBars.length)} '
        'tylko 1 element. To zwykle znak, że plan trudno domknąć dla tej partii.',
      );
    }

    if (totalSawLossMm >= result.totalWasteMm && totalSawLossMm > 0) {
      warnings.add(
        'Łączna strata na grubości piły to ${unit.format(totalSawLossMm)}, czyli co najmniej tyle co odpad końcowy.',
      );
    }

    if (result.utilizationPercent < 85) {
      warnings.add(
        'Wykorzystanie materiału spada poniżej 85%, więc ten plan ma jeszcze duży margines do poprawy.',
      );
    }

    if (highWasteBars.isNotEmpty || singleCutBars.isNotEmpty) {
      suggestions.add(
        'Dla tej partii warto sprawdzić drugi wariant długości materiału bazowego albo rozdzielenie produkcji na krótsze serie.',
      );
    }

    if (totalSawLossMm > 0) {
      suggestions.add(
        'Grubość piły zabiera łącznie ${unit.format(totalSawLossMm)}. Jeśli technologia pozwala, mniejsza grubość może zauważalnie poprawić wynik.',
      );
    }

    if (repeatedPatterns.isNotEmpty) {
      suggestions.add(
        'Powtarzalne układy warto grupować przy realizacji zlecenia, bo skracają przygotowanie stanowiska i zmniejszają ryzyko pomyłki.',
      );
    }

    if (suggestions.isEmpty) {
      suggestions.add(
        'Plan wygląda stabilnie. Jeśli chcesz jeszcze go dociskać, porównaj wynik dla innej długości sztangi lub innej kolejności produkcyjnej.',
      );
    }

    final headline = switch (score) {
      >= 96 => 'Plan wygląda bardzo mocno.',
      >= 88 => 'Plan jest solidny i dobrze domknięty.',
      >= 78 => 'Plan jest poprawny, ale widać rezerwę.',
      _ => 'Plan wymaga jeszcze dopracowania.',
    };

    final summary =
        'Lokalny asystent przeanalizował ${result.barCount} ${_pluralize('sztangę', 'sztangi', result.barCount)} '
        'dla $totalPieces ${_pluralize('elementu', 'elementów', totalPieces)}. '
        'Łączny odpad to ${unit.format(result.totalWasteMm)}, a wykorzystanie materiału wynosi '
        '${_formatPercent(result.utilizationPercent)}%.';

    return LocalAiAnalysis(
      score: score,
      statusLabel: statusLabel,
      headline: headline,
      summary: summary,
      highlights: highlights,
      warnings: warnings,
      suggestions: suggestions,
    );
  }

  List<_RepeatedPattern> _findRepeatedPatterns(List<BarPlan> bars) {
    final grouped = <String, List<BarPlan>>{};
    for (final bar in bars) {
      final key = bar.cutsMm.join('-');
      grouped.putIfAbsent(key, () => <BarPlan>[]).add(bar);
    }

    final repeated =
        grouped.values
            .where((barsForPattern) => barsForPattern.length > 1)
            .map(
              (barsForPattern) => _RepeatedPattern(
                exampleBar: barsForPattern.first,
                count: barsForPattern.length,
              ),
            )
            .toList()
          ..sort((left, right) => right.count.compareTo(left.count));

    return repeated;
  }

  String _formatPattern(BarPlan bar, MeasurementUnit unit) {
    final parts = [
      for (var index = 0; index < bar.cutsMm.length && index < 4; index++)
        unit.format(bar.cutsMm[index]),
    ];
    if (bar.cutsMm.length > 4) {
      parts.add('+${bar.cutsMm.length - 4}');
    }
    return parts.join(' • ');
  }

  String _formatPercent(double value) {
    return value.toStringAsFixed(1).replaceAll('.', ',');
  }

  String _statusLabel(int score) {
    return switch (score) {
      >= 96 => 'Bardzo dobry',
      >= 88 => 'Dobry',
      >= 78 => 'Średni',
      _ => 'Do poprawy',
    };
  }

  String _pluralize(String singular, String plural, int count) {
    return count == 1 ? singular : plural;
  }
}

class _RepeatedPattern {
  const _RepeatedPattern({required this.exampleBar, required this.count});

  final BarPlan exampleBar;
  final int count;
}
