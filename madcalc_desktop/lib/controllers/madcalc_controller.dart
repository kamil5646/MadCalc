import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

import '../models/bar_plan.dart';
import '../models/cut_item.dart';
import '../models/cut_settings.dart';
import '../models/measurement_unit.dart';
import '../models/optimization_result.dart';
import '../services/cut_optimizer.dart';
import '../services/pdf_report_builder.dart';
import '../services/state_persistence.dart';

class MadCalcController extends ChangeNotifier {
  MadCalcController({
    StatePersistence? persistence,
    PdfReportBuilder? pdfReportBuilder,
  })  : _persistence = persistence ?? StatePersistence(),
        _pdfReportBuilder = pdfReportBuilder ?? PdfReportBuilder();

  static Future<MadCalcController> create() async {
    final controller = MadCalcController();
    await controller._loadState();
    return controller;
  }

  final StatePersistence _persistence;
  final PdfReportBuilder _pdfReportBuilder;

  MeasurementUnit unit = MeasurementUnit.centimeters;
  String itemLengthInput = '';
  String itemQuantityInput = '1';
  String stockLengthInput = '600';
  String sawThicknessInput = '0,3';
  List<CutItem> items = <CutItem>[];
  OptimizationResult? result;
  CutSettings? generatedSettings;
  DateTime? generatedAt;
  bool isGenerating = false;
  String? lastExportPath;

  String? _editingItemId;

  bool get isEditingItem => _editingItemId != null;

  String get itemActionTitle => isEditingItem ? 'Zapisz element' : 'Dodaj element';

  String get itemHint {
    return switch (unit) {
      MeasurementUnit.centimeters => 'Domyślnie pracujesz w centymetrach.',
      MeasurementUnit.millimeters => 'Pracujesz w milimetrach.',
    };
  }

  bool get canGenerate {
    return items.isNotEmpty && !isGenerating && _readSettings(showErrors: false) != null;
  }

  bool get canExport {
    return result != null && generatedSettings != null && generatedAt != null;
  }

  Future<void> _loadState() async {
    final persisted = await _persistence.load();
    if (persisted != null) {
      unit = persisted.unit;
      items = persisted.items;
      stockLengthInput = unit.format(persisted.stockLengthMm, includeUnit: false);
      sawThicknessInput = unit.format(persisted.sawThicknessMm, includeUnit: false);
      result = persisted.result;
      generatedSettings = persisted.generatedSettings;
      generatedAt = persisted.generatedAt;
    }
  }

  void updateItemLengthInput(String value) {
    itemLengthInput = value;
    notifyListeners();
  }

  void updateItemQuantityInput(String value) {
    itemQuantityInput = value;
    notifyListeners();
  }

  void updateStockLengthInput(String value) {
    stockLengthInput = value;
    _invalidateGeneratedResult();
    _persistLater();
    notifyListeners();
  }

  void updateSawThicknessInput(String value) {
    sawThicknessInput = value;
    _invalidateGeneratedResult();
    _persistLater();
    notifyListeners();
  }

  void switchUnit(MeasurementUnit nextUnit) {
    if (nextUnit == unit) {
      return;
    }

    itemLengthInput = _convertDisplayedValue(itemLengthInput, from: unit, to: nextUnit);
    stockLengthInput = _convertDisplayedValue(stockLengthInput, from: unit, to: nextUnit);
    sawThicknessInput = _convertDisplayedValue(sawThicknessInput, from: unit, to: nextUnit);
    unit = nextUnit;
    _persistLater();
    notifyListeners();
  }

  String? saveCurrentItem() {
    final lengthMm = unit.parse(itemLengthInput);
    if (lengthMm == null || lengthMm <= 0) {
      return 'Podaj dodatnią długość elementu.';
    }

    final quantity = int.tryParse(itemQuantityInput.trim());
    if (quantity == null || quantity <= 0) {
      return 'Podaj ilość sztuk większą od zera.';
    }

    final item = CutItem(
      id: _editingItemId ?? _nextItemId(),
      lengthMm: lengthMm,
      quantity: quantity,
    );

    if (_editingItemId == null) {
      items = [...items, item];
    } else {
      items = items
          .map((existing) => existing.id == _editingItemId ? item : existing)
          .toList();
    }

    cancelEditing(notify: false);
    _invalidateGeneratedResult();
    _persistLater();
    notifyListeners();
    return null;
  }

  void beginEditing(CutItem item) {
    _editingItemId = item.id;
    itemLengthInput = unit.format(item.lengthMm, includeUnit: false);
    itemQuantityInput = '${item.quantity}';
    notifyListeners();
  }

  void cancelEditing({bool notify = true}) {
    _editingItemId = null;
    itemLengthInput = '';
    itemQuantityInput = '1';
    if (notify) {
      notifyListeners();
    }
  }

  void deleteItem(CutItem item) {
    items = items.where((existing) => existing.id != item.id).toList();
    if (_editingItemId == item.id) {
      cancelEditing(notify: false);
    }
    _invalidateGeneratedResult();
    _persistLater();
    notifyListeners();
  }

  void clearAll() {
    unit = MeasurementUnit.centimeters;
    itemLengthInput = '';
    itemQuantityInput = '1';
    stockLengthInput = '600';
    sawThicknessInput = '0,3';
    items = <CutItem>[];
    result = null;
    generatedSettings = null;
    generatedAt = null;
    lastExportPath = null;
    _editingItemId = null;
    _persistLater();
    notifyListeners();
  }

  void loadSampleData() {
    items = <CutItem>[
      CutItem(id: _nextItemId(), lengthMm: 1200, quantity: 4),
      CutItem(id: _nextItemId(), lengthMm: 960, quantity: 3),
      CutItem(id: _nextItemId(), lengthMm: 450, quantity: 5),
    ];
    unit = MeasurementUnit.centimeters;
    stockLengthInput = '600';
    sawThicknessInput = '0,3';
    lastExportPath = null;
    _editingItemId = null;
    itemLengthInput = '';
    itemQuantityInput = '1';
    _invalidateGeneratedResult();
    _persistLater();
    notifyListeners();
  }

  Future<String?> generatePlan() async {
    final settings = _readSettings(showErrors: true);
    if (settings == null) {
      return 'Sprawdź długość sztangi i grubość piły.';
    }
    if (items.isEmpty) {
      return 'Dodaj przynajmniej jeden element do cięcia.';
    }

    final existingBarNames = <int, String>{
      for (final bar in result?.bars ?? <BarPlan>[]) bar.barIndex: bar.name,
    };

    isGenerating = true;
    notifyListeners();

    try {
      final optimizedJson = await compute<Map<String, dynamic>, Map<String, dynamic>>(
        optimizeCutsInBackground,
        <String, dynamic>{
          'items': items.map((item) => item.toJson()).toList(),
          'settings': settings.toJson(),
        },
      );

      final optimized = OptimizationResult.fromJson(optimizedJson);
      final namedBars = optimized.bars
          .map(
            (bar) => bar.copyWith(
              name: existingBarNames[bar.barIndex] ?? bar.name,
            ),
          )
          .toList();

      result = optimized.copyWith(bars: namedBars);
      generatedSettings = settings;
      generatedAt = DateTime.now();
      lastExportPath = null;
      _persistLater();
      return null;
    } on CutOptimizationException catch (error) {
      return error.message;
    } catch (error) {
      return '$error';
    } finally {
      isGenerating = false;
      notifyListeners();
    }
  }

  Future<String?> exportPdf() async {
    final currentResult = result;
    final currentSettings = generatedSettings;
    final currentGeneratedAt = generatedAt;

    if (currentResult == null || currentSettings == null || currentGeneratedAt == null) {
      return 'Najpierw wygeneruj plan cięcia.';
    }

    final location = await getSaveLocation(
      suggestedName: _suggestedPdfFileName(currentGeneratedAt),
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(label: 'PDF', extensions: <String>['pdf']),
      ],
    );

    if (location == null) {
      return null;
    }

    try {
      final data = await _pdfReportBuilder.build(
        items: items,
        settings: currentSettings,
        result: currentResult,
        unit: unit,
        generatedAt: currentGeneratedAt,
      );
      final path = location.path.toLowerCase().endsWith('.pdf')
          ? location.path
          : '${location.path}.pdf';
      final file = File(path);
      await file.writeAsBytes(data, flush: true);
      lastExportPath = path;
      notifyListeners();
      return 'PDF zapisany w: $path';
    } catch (_) {
      return 'Nie udało się zapisać raportu PDF.';
    }
  }

  String formatLength(int valueMm) {
    return unit.format(valueMm);
  }

  String formatPercent(double value) {
    return value.toStringAsFixed(1).replaceAll('.', ',');
  }

  int totalSawThickness(BarPlan bar) {
    final settings = generatedSettings;
    if (settings == null) {
      return 0;
    }
    return (bar.cutCount - 1).clamp(0, bar.cutCount) * settings.sawThicknessMm;
  }

  void renameBar(int barId, String value) {
    final currentResult = result;
    if (currentResult == null) {
      return;
    }
    final index = currentResult.bars.indexWhere((bar) => bar.id == barId);
    if (index == -1) {
      return;
    }

    final updatedBars = [...currentResult.bars];
    updatedBars[index] = updatedBars[index].copyWith(name: value);
    result = currentResult.copyWith(bars: updatedBars);
    _persistLater();
    notifyListeners();
  }

  String displayName(BarPlan bar) {
    return bar.displayName;
  }

  String? _readableSettingsError() {
    if (unit.parse(stockLengthInput) == null || unit.parse(stockLengthInput)! <= 0) {
      return 'Długość sztangi musi być większa od zera.';
    }
    final sawThicknessMm = unit.parse(sawThicknessInput);
    if (sawThicknessMm == null || sawThicknessMm < 0) {
      return 'Grubość piły nie może być ujemna.';
    }
    return null;
  }

  CutSettings? _readSettings({required bool showErrors}) {
    final stockLengthMm = unit.parse(stockLengthInput);
    if (stockLengthMm == null || stockLengthMm <= 0) {
      return null;
    }
    final sawThicknessMm = unit.parse(sawThicknessInput);
    if (sawThicknessMm == null || sawThicknessMm < 0) {
      return null;
    }

    final error = showErrors ? _readableSettingsError() : null;
    if (error != null) {
      return null;
    }

    return CutSettings(
      stockLengthMm: stockLengthMm,
      sawThicknessMm: sawThicknessMm,
    );
  }

  void _invalidateGeneratedResult() {
    result = null;
    generatedSettings = null;
    generatedAt = null;
    lastExportPath = null;
  }

  void _persistLater() {
    final stockLengthMm = unit.parse(stockLengthInput) ?? 6000;
    final sawThicknessMm = unit.parse(sawThicknessInput) ?? 3;
    unawaited(
      _persistence.save(
        PersistedState(
          unit: unit,
          items: items,
          stockLengthMm: stockLengthMm,
          sawThicknessMm: sawThicknessMm,
          result: result,
          generatedSettings: generatedSettings,
          generatedAt: generatedAt,
        ),
      ),
    );
  }

  String _convertDisplayedValue(
    String value, {
    required MeasurementUnit from,
    required MeasurementUnit to,
  }) {
    final valueMm = from.parse(value);
    if (valueMm == null) {
      return value;
    }
    return to.format(valueMm, includeUnit: false);
  }

  String _suggestedPdfFileName(DateTime dateTime) {
    final year = dateTime.year.toString();
    final month = dateTime.month.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return 'MadCalc-$year$month$day-$hour$minute.pdf';
  }

  String _nextItemId() {
    return '${DateTime.now().microsecondsSinceEpoch}-${_idSeed++}';
  }

  int _idSeed = 0;
}
