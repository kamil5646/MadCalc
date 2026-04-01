import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/cut_item.dart';
import '../models/cut_settings.dart';
import '../models/measurement_unit.dart';
import '../models/optimization_result.dart';

class PersistedState {
  PersistedState({
    required this.unit,
    required this.items,
    required this.stockLengthMm,
    required this.sawThicknessMm,
    required this.result,
    required this.generatedSettings,
    required this.generatedAt,
  });

  final MeasurementUnit unit;
  final List<CutItem> items;
  final int stockLengthMm;
  final int sawThicknessMm;
  final OptimizationResult? result;
  final CutSettings? generatedSettings;
  final DateTime? generatedAt;

  Map<String, dynamic> toJson() {
    return {
      'unit': unit.name,
      'items': items.map((item) => item.toJson()).toList(),
      'stockLengthMm': stockLengthMm,
      'sawThicknessMm': sawThicknessMm,
      'result': result?.toJson(),
      'generatedSettings': generatedSettings?.toJson(),
      'generatedAt': generatedAt?.toIso8601String(),
    };
  }

  factory PersistedState.fromJson(Map<String, dynamic> json) {
    return PersistedState(
      unit: MeasurementUnit.fromRaw(json['unit'] as String? ?? ''),
      items: (json['items'] as List<dynamic>? ?? [])
          .map((item) => CutItem.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList(),
      stockLengthMm: json['stockLengthMm'] as int? ?? 6000,
      sawThicknessMm: json['sawThicknessMm'] as int? ?? 3,
      result: json['result'] == null
          ? null
          : OptimizationResult.fromJson(
              Map<String, dynamic>.from(json['result'] as Map),
            ),
      generatedSettings: json['generatedSettings'] == null
          ? null
          : CutSettings.fromJson(
              Map<String, dynamic>.from(json['generatedSettings'] as Map),
            ),
      generatedAt: json['generatedAt'] == null
          ? null
          : DateTime.tryParse(json['generatedAt'] as String),
    );
  }
}

class StatePersistence {
  static const _storageKey = 'pl.madmagsystem.madcalc.desktop.persistence.v1';

  Future<PersistedState?> load() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_storageKey);
    if (encoded == null || encoded.isEmpty) {
      return null;
    }

    final decoded = jsonDecode(encoded);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    return PersistedState.fromJson(decoded);
  }

  Future<void> save(PersistedState state) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_storageKey, jsonEncode(state.toJson()));
  }
}
