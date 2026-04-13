import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:madcalc_desktop/models/bar_plan.dart';
import 'package:madcalc_desktop/models/calculation_history_entry.dart';
import 'package:madcalc_desktop/models/cut_item.dart';
import 'package:madcalc_desktop/models/cut_settings.dart';
import 'package:madcalc_desktop/models/measurement_unit.dart';
import 'package:madcalc_desktop/models/optimization_result.dart';
import 'package:madcalc_desktop/services/state_persistence.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StatePersistence', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('saves and loads current state with history entries', () async {
      final persistence = StatePersistence();
      final savedAt = DateTime(2026, 4, 13, 21, 15);
      final generatedAt = DateTime(2026, 4, 13, 21, 10);

      final entry = CalculationHistoryEntry(
        id: 'history-1',
        savedAt: savedAt,
        unit: MeasurementUnit.centimeters,
        items: [
          CutItem(id: 'a', lengthMm: 1200, quantity: 4),
          CutItem(id: 'b', lengthMm: 960, quantity: 2),
        ],
        settings: const CutSettings(stockLengthMm: 6000, sawThicknessMm: 3),
        result: OptimizationResult(
          barCount: 2,
          totalWasteMm: 240,
          utilizationPercent: 98.0,
          bars: [
            BarPlan(
              barIndex: 1,
              name: 'Sztanga A',
              cutsMm: [1200, 1200, 960, 960],
              usedLengthMm: 4329,
              wasteMm: 1671,
            ),
            BarPlan(
              barIndex: 2,
              name: 'Sztanga B',
              cutsMm: [1200, 1200],
              usedLengthMm: 2403,
              wasteMm: 3597,
            ),
          ],
        ),
        generatedAt: generatedAt,
      );

      await persistence.save(
        PersistedState(
          unit: MeasurementUnit.centimeters,
          items: entry.items,
          stockLengthMm: 6000,
          sawThicknessMm: 3,
          result: entry.result,
          generatedSettings: entry.settings,
          generatedAt: generatedAt,
          historyEntries: [entry],
          activeHistoryEntryId: entry.id,
        ),
      );

      final loaded = await persistence.load();

      expect(loaded, isNotNull);
      expect(loaded!.historyEntries, hasLength(1));
      expect(loaded.activeHistoryEntryId, entry.id);
      expect(loaded.historyEntries.first.result.barCount, 2);
      expect(loaded.historyEntries.first.items.first.lengthMm, 1200);
      expect(loaded.historyEntries.first.savedAt, savedAt);
    });

    test('loads older saved payloads without history', () async {
      SharedPreferences.setMockInitialValues({
        'pl.madmagsystem.madcalc.desktop.persistence.v1': jsonEncode({
          'unit': 'centimeters',
          'items': [
            {'id': 'a', 'lengthMm': 1200, 'quantity': 4},
          ],
          'stockLengthMm': 6000,
          'sawThicknessMm': 3,
          'result': null,
          'generatedSettings': null,
          'generatedAt': null,
        }),
      });

      final persistence = StatePersistence();
      final loaded = await persistence.load();

      expect(loaded, isNotNull);
      expect(loaded!.historyEntries, isEmpty);
      expect(loaded.activeHistoryEntryId, isNull);
      expect(loaded.items.single.quantity, 4);
    });
  });
}
