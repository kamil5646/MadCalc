import 'cut_item.dart';
import 'cut_settings.dart';
import 'measurement_unit.dart';
import 'optimization_result.dart';

class CalculationHistoryEntry {
  const CalculationHistoryEntry({
    required this.id,
    required this.savedAt,
    required this.unit,
    required this.items,
    required this.settings,
    required this.result,
    required this.generatedAt,
  });

  final String id;
  final DateTime savedAt;
  final MeasurementUnit unit;
  final List<CutItem> items;
  final CutSettings settings;
  final OptimizationResult result;
  final DateTime generatedAt;

  int get totalPieces => items.fold<int>(0, (sum, item) => sum + item.quantity);

  int get itemTypesCount => items.length;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'savedAt': savedAt.toIso8601String(),
      'unit': unit.name,
      'items': items.map((item) => item.toJson()).toList(),
      'settings': settings.toJson(),
      'result': result.toJson(),
      'generatedAt': generatedAt.toIso8601String(),
    };
  }

  factory CalculationHistoryEntry.fromJson(Map<String, dynamic> json) {
    return CalculationHistoryEntry(
      id: json['id'] as String,
      savedAt:
          DateTime.tryParse(json['savedAt'] as String? ?? '') ?? DateTime.now(),
      unit: MeasurementUnit.fromRaw(json['unit'] as String? ?? ''),
      items: (json['items'] as List<dynamic>? ?? [])
          .map(
            (item) => CutItem.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(),
      settings: CutSettings.fromJson(
        Map<String, dynamic>.from(json['settings'] as Map),
      ),
      result: OptimizationResult.fromJson(
        Map<String, dynamic>.from(json['result'] as Map),
      ),
      generatedAt:
          DateTime.tryParse(json['generatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
