import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/app_update_info.dart';
import '../models/bar_plan.dart';
import '../models/calculation_history_entry.dart';
import '../models/cut_item.dart';
import '../models/cut_settings.dart';
import '../models/local_ai_analysis.dart';
import '../models/measurement_unit.dart';
import '../models/optimization_result.dart';
import '../services/app_update_service.dart';
import '../services/cut_optimizer.dart';
import '../services/local_ai_analysis_service.dart';
import '../services/pdf_report_builder.dart';
import '../services/state_persistence.dart';

class MadCalcController extends ChangeNotifier {
  MadCalcController({
    StatePersistence? persistence,
    AppUpdateService? updateService,
    LocalAiAnalysisService? localAiAnalysisService,
  }) : _persistence = persistence ?? StatePersistence(),
       _updateService = updateService ?? AppUpdateService(),
       _localAiAnalysisService =
           localAiAnalysisService ?? LocalAiAnalysisService();

  static Future<MadCalcController> create() async {
    final controller = MadCalcController();
    await controller._loadState();
    return controller;
  }

  final StatePersistence _persistence;
  final AppUpdateService _updateService;
  final LocalAiAnalysisService _localAiAnalysisService;

  MeasurementUnit unit = MeasurementUnit.centimeters;
  String itemLengthInput = '';
  String itemQuantityInput = '1';
  String stockLengthInput = '600';
  String sawThicknessInput = '0,3';
  List<CutItem> items = <CutItem>[];
  OptimizationResult? result;
  LocalAiAnalysis? localAiAnalysis;
  CutSettings? generatedSettings;
  DateTime? generatedAt;
  bool isGenerating = false;
  bool isExporting = false;
  bool isPrinting = false;
  bool isCheckingUpdates = false;
  bool isOpeningUpdate = false;
  String? lastExportPath;
  String? currentVersion;
  AppUpdateInfo? availableUpdate;
  List<CalculationHistoryEntry> historyEntries = <CalculationHistoryEntry>[];

  String? _editingItemId;
  bool _runtimeInitialized = false;
  String? _activeHistoryEntryId;

  static const _historyLimit = 12;

  bool get isEditingItem => _editingItemId != null;

  String get itemActionTitle =>
      isEditingItem ? 'Zapisz element' : 'Dodaj element';

  String get itemHint {
    return switch (unit) {
      MeasurementUnit.centimeters => 'Domyślnie pracujesz w centymetrach.',
      MeasurementUnit.millimeters => 'Pracujesz w milimetrach.',
    };
  }

  bool get canGenerate {
    return items.isNotEmpty &&
        !isGenerating &&
        _readSettings(showErrors: false) != null;
  }

  bool get canExport {
    return result != null &&
        generatedSettings != null &&
        generatedAt != null &&
        !isGenerating &&
        !isExporting &&
        !isPrinting;
  }

  bool get canPrint {
    return result != null &&
        generatedSettings != null &&
        generatedAt != null &&
        !isGenerating &&
        !isExporting &&
        !isPrinting;
  }

  bool get hasHistory => historyEntries.isNotEmpty;

  String get versionBadgeLabel {
    final version = currentVersion;
    if (version == null || version.isEmpty) {
      return 'Wersja...';
    }
    return 'v$version';
  }

  Future<void> _loadState() async {
    final persisted = await _persistence.load();
    if (persisted != null) {
      unit = persisted.unit;
      items = persisted.items;
      stockLengthInput = unit.format(
        persisted.stockLengthMm,
        includeUnit: false,
      );
      sawThicknessInput = unit.format(
        persisted.sawThicknessMm,
        includeUnit: false,
      );
      result = persisted.result;
      generatedSettings = persisted.generatedSettings;
      generatedAt = persisted.generatedAt;
      historyEntries = persisted.historyEntries;
      _activeHistoryEntryId = persisted.activeHistoryEntryId;
      if (_activeHistoryEntryId != null &&
          !historyEntries.any((entry) => entry.id == _activeHistoryEntryId)) {
        _activeHistoryEntryId = null;
      }
      _refreshLocalAiAnalysis();
    }
  }

  Future<void> initializeRuntimeServices() async {
    if (_runtimeInitialized) {
      return;
    }
    _runtimeInitialized = true;

    try {
      currentVersion = await _updateService.loadCurrentVersion();
      notifyListeners();
    } catch (_) {
      // Brak odczytu wersji nie powinien blokować uruchomienia aplikacji.
    }

    unawaited(checkForUpdates(silent: true));
  }

  Future<String?> checkForUpdates({bool silent = false}) async {
    if (isCheckingUpdates) {
      return silent ? null : 'Sprawdzanie aktualizacji już trwa.';
    }

    isCheckingUpdates = true;
    notifyListeners();

    try {
      final check = await _updateService.checkForUpdate(
        currentVersion: currentVersion,
      );
      currentVersion = check.currentVersion;
      availableUpdate = check.availableUpdate;

      if (check.availableUpdate == null) {
        return silent ? null : 'Masz już najnowszą wersję MadCalc.';
      }

      return silent
          ? null
          : 'Dostępna jest wersja ${check.availableUpdate!.latestVersion}.';
    } on AppUpdateException catch (error) {
      return silent ? null : error.message;
    } catch (_) {
      return silent ? null : 'Nie udało się sprawdzić aktualizacji MadCalc.';
    } finally {
      isCheckingUpdates = false;
      notifyListeners();
    }
  }

  Future<String?> openAvailableUpdate() async {
    final update = availableUpdate;
    if (update == null) {
      return 'Brak nowej aktualizacji do pobrania.';
    }

    isOpeningUpdate = true;
    notifyListeners();

    try {
      final opened = await launchUrl(
        Uri.parse(update.downloadUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        return 'Nie udało się otworzyć linku do aktualizacji.';
      }

      return update.hasDirectDownload
          ? 'Otwarto pobieranie aktualizacji.'
          : 'Otwarto stronę release z aktualizacją.';
    } catch (_) {
      return 'Nie udało się otworzyć aktualizacji.';
    } finally {
      isOpeningUpdate = false;
      notifyListeners();
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

    itemLengthInput = _convertDisplayedValue(
      itemLengthInput,
      from: unit,
      to: nextUnit,
    );
    stockLengthInput = _convertDisplayedValue(
      stockLengthInput,
      from: unit,
      to: nextUnit,
    );
    sawThicknessInput = _convertDisplayedValue(
      sawThicknessInput,
      from: unit,
      to: nextUnit,
    );
    unit = nextUnit;
    _refreshLocalAiAnalysis();
    _syncActiveHistoryEntryWithCurrentState();
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
    localAiAnalysis = null;
    generatedSettings = null;
    generatedAt = null;
    lastExportPath = null;
    _editingItemId = null;
    _activeHistoryEntryId = null;
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
      final optimizedJson =
          await compute<Map<String, dynamic>, Map<String, dynamic>>(
            optimizeCutsInBackground,
            <String, dynamic>{
              'items': items.map((item) => item.toJson()).toList(),
              'settings': settings.toJson(),
            },
          );

      final optimized = OptimizationResult.fromJson(optimizedJson);
      final namedBars = optimized.bars
          .map(
            (bar) =>
                bar.copyWith(name: existingBarNames[bar.barIndex] ?? bar.name),
          )
          .toList();

      result = optimized.copyWith(bars: namedBars);
      generatedSettings = settings;
      generatedAt = DateTime.now();
      _refreshLocalAiAnalysis();
      lastExportPath = null;
      _saveCurrentCalculationToHistory();
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
    final snapshot = _pdfSnapshot();
    if (snapshot == null) {
      return 'Najpierw wygeneruj plan cięcia.';
    }

    final location = await getSaveLocation(
      suggestedName: _suggestedPdfFileName(snapshot.generatedAt),
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(label: 'PDF', extensions: <String>['pdf']),
      ],
    );

    if (location == null) {
      return null;
    }

    isExporting = true;
    notifyListeners();

    try {
      final data = await _buildPdfData(snapshot);
      final path = location.path.toLowerCase().endsWith('.pdf')
          ? location.path
          : '${location.path}.pdf';
      final file = File(path);
      await file.writeAsBytes(data, flush: true);
      lastExportPath = path;
      return 'PDF zapisany w: $path';
    } on TimeoutException {
      return 'Tworzenie PDF trwało wyjątkowo długo. Spróbuj ponowić eksport, ale raport nie powinien już wywalać się tylko dlatego, że jest większy.';
    } catch (_) {
      return 'Nie udało się zapisać raportu PDF.';
    } finally {
      isExporting = false;
      notifyListeners();
    }
  }

  Future<String?> printPdf() async {
    final snapshot = _pdfSnapshot();
    if (snapshot == null) {
      return 'Najpierw wygeneruj plan cięcia.';
    }

    isPrinting = true;
    notifyListeners();

    try {
      final data = await _buildPdfData(snapshot);
      await Printing.layoutPdf(
        name: _suggestedPdfFileName(snapshot.generatedAt),
        onLayout: (_) async => data,
      );
      return 'Otwarto okno drukowania.';
    } on TimeoutException {
      return 'Przygotowanie PDF do druku trwało wyjątkowo długo. Spróbuj jeszcze raz dla aktualnego planu.';
    } catch (_) {
      return 'Nie udało się otworzyć okna drukowania.';
    } finally {
      isPrinting = false;
      notifyListeners();
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
    _syncActiveHistoryEntryWithCurrentState();
    _persistLater();
    notifyListeners();
  }

  String displayName(BarPlan bar) {
    return bar.displayName;
  }

  void loadHistoryEntry(CalculationHistoryEntry entry) {
    unit = entry.unit;
    items = [...entry.items];
    stockLengthInput = unit.format(
      entry.settings.stockLengthMm,
      includeUnit: false,
    );
    sawThicknessInput = unit.format(
      entry.settings.sawThicknessMm,
      includeUnit: false,
    );
    result = entry.result;
    generatedSettings = entry.settings;
    generatedAt = entry.generatedAt;
    _refreshLocalAiAnalysis();
    lastExportPath = null;
    _editingItemId = null;
    itemLengthInput = '';
    itemQuantityInput = '1';
    _activeHistoryEntryId = entry.id;
    _persistLater();
    notifyListeners();
  }

  void deleteHistoryEntry(CalculationHistoryEntry entry) {
    historyEntries = historyEntries
        .where((existing) => existing.id != entry.id)
        .toList(growable: false);
    if (_activeHistoryEntryId == entry.id) {
      _activeHistoryEntryId = null;
    }
    _persistLater();
    notifyListeners();
  }

  void clearHistory() {
    historyEntries = <CalculationHistoryEntry>[];
    _activeHistoryEntryId = null;
    _persistLater();
    notifyListeners();
  }

  String formatHistoryTimestamp(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final year = value.year.toString();
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$day.$month.$year $hour:$minute';
  }

  String? _readableSettingsError() {
    if (unit.parse(stockLengthInput) == null ||
        unit.parse(stockLengthInput)! <= 0) {
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
    localAiAnalysis = null;
    generatedSettings = null;
    generatedAt = null;
    lastExportPath = null;
    _activeHistoryEntryId = null;
  }

  void _refreshLocalAiAnalysis() {
    final currentResult = result;
    final currentSettings = generatedSettings;
    if (currentResult == null || currentSettings == null) {
      localAiAnalysis = null;
      return;
    }

    localAiAnalysis = _localAiAnalysisService.analyze(
      items: items,
      settings: currentSettings,
      result: currentResult,
      unit: unit,
    );
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
          historyEntries: historyEntries,
          activeHistoryEntryId: _activeHistoryEntryId,
        ),
      ),
    );
  }

  Duration _pdfExportTimeout(OptimizationResult result) {
    final baseSeconds = switch (Platform.operatingSystem) {
      'windows' => 180,
      'android' => 90,
      _ => 60,
    };
    final extraSeconds = ((result.bars.length / 50).ceil()) * 15;
    return Duration(seconds: baseSeconds + extraSeconds);
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

  _PdfSnapshot? _pdfSnapshot() {
    final currentResult = result;
    final currentSettings = generatedSettings;
    final currentGeneratedAt = generatedAt;

    if (currentResult == null ||
        currentSettings == null ||
        currentGeneratedAt == null) {
      return null;
    }

    return _PdfSnapshot(
      items: List<CutItem>.from(items),
      settings: currentSettings,
      result: currentResult,
      unit: unit,
      generatedAt: currentGeneratedAt,
    );
  }

  Future<Uint8List> _buildPdfData(_PdfSnapshot snapshot) async {
    final fonts = await PdfFontAssets.load();
    return compute<Map<String, dynamic>, Uint8List>(
      buildPdfInBackground,
      <String, dynamic>{
        'items': snapshot.items.map((item) => item.toJson()).toList(),
        'settings': snapshot.settings.toJson(),
        'result': snapshot.result.toJson(),
        'unit': snapshot.unit.name,
        'generatedAt': snapshot.generatedAt.toIso8601String(),
        'regularFontBytes': fonts.regularBytes,
        'boldFontBytes': fonts.boldBytes,
      },
    ).timeout(_pdfExportTimeout(snapshot.result));
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

  void _saveCurrentCalculationToHistory() {
    final snapshot = _historySnapshot();
    if (snapshot == null) {
      return;
    }

    final historyEntryId = _activeHistoryEntryId ?? _nextHistoryId();
    _activeHistoryEntryId = historyEntryId;
    _upsertHistoryEntry(
      CalculationHistoryEntry(
        id: historyEntryId,
        savedAt: DateTime.now(),
        unit: snapshot.unit,
        items: snapshot.items,
        settings: snapshot.settings,
        result: snapshot.result,
        generatedAt: snapshot.generatedAt,
      ),
    );
  }

  void _syncActiveHistoryEntryWithCurrentState() {
    if (_activeHistoryEntryId == null) {
      return;
    }

    final snapshot = _historySnapshot();
    if (snapshot == null) {
      return;
    }

    _upsertHistoryEntry(
      CalculationHistoryEntry(
        id: _activeHistoryEntryId!,
        savedAt: DateTime.now(),
        unit: snapshot.unit,
        items: snapshot.items,
        settings: snapshot.settings,
        result: snapshot.result,
        generatedAt: snapshot.generatedAt,
      ),
    );
  }

  void _upsertHistoryEntry(CalculationHistoryEntry entry) {
    final updated = <CalculationHistoryEntry>[entry];
    updated.addAll(
      historyEntries
          .where((existing) => existing.id != entry.id)
          .take(_historyLimit - 1),
    );
    historyEntries = updated;
  }

  _HistorySnapshot? _historySnapshot() {
    final currentResult = result;
    final currentSettings = generatedSettings;
    final currentGeneratedAt = generatedAt;
    if (currentResult == null ||
        currentSettings == null ||
        currentGeneratedAt == null) {
      return null;
    }

    return _HistorySnapshot(
      unit: unit,
      items: List<CutItem>.from(items),
      settings: currentSettings,
      result: currentResult,
      generatedAt: currentGeneratedAt,
    );
  }

  String _nextHistoryId() {
    return 'history-${DateTime.now().microsecondsSinceEpoch}';
  }
}

class _PdfSnapshot {
  const _PdfSnapshot({
    required this.items,
    required this.settings,
    required this.result,
    required this.unit,
    required this.generatedAt,
  });

  final List<CutItem> items;
  final CutSettings settings;
  final OptimizationResult result;
  final MeasurementUnit unit;
  final DateTime generatedAt;
}

class _HistorySnapshot {
  const _HistorySnapshot({
    required this.unit,
    required this.items,
    required this.settings,
    required this.result,
    required this.generatedAt,
  });

  final MeasurementUnit unit;
  final List<CutItem> items;
  final CutSettings settings;
  final OptimizationResult result;
  final DateTime generatedAt;
}
