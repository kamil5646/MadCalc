import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/madcalc_controller.dart';
import '../models/app_update_info.dart';
import '../models/bar_plan.dart';
import '../models/calculation_history_entry.dart';
import '../models/cut_item.dart';
import '../models/local_ai_analysis.dart';
import '../models/measurement_unit.dart';

class HomePage extends StatefulWidget {
  const HomePage({required this.controller, super.key});

  final MadCalcController controller;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final TextEditingController _itemLengthController;
  late final TextEditingController _itemQuantityController;
  late final TextEditingController _stockLengthController;
  late final TextEditingController _sawThicknessController;
  late final FocusNode _itemLengthFocusNode;
  late final FocusNode _itemQuantityFocusNode;

  @override
  void initState() {
    super.initState();
    _itemLengthController = TextEditingController(
      text: widget.controller.itemLengthInput,
    );
    _itemQuantityController = TextEditingController(
      text: widget.controller.itemQuantityInput,
    );
    _stockLengthController = TextEditingController(
      text: widget.controller.stockLengthInput,
    );
    _sawThicknessController = TextEditingController(
      text: widget.controller.sawThicknessInput,
    );
    _itemLengthFocusNode = FocusNode();
    _itemQuantityFocusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(widget.controller.initializeRuntimeServices());
    });
  }

  @override
  void dispose() {
    _itemLengthController.dispose();
    _itemQuantityController.dispose();
    _stockLengthController.dispose();
    _sawThicknessController.dispose();
    _itemLengthFocusNode.dispose();
    _itemQuantityFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        _syncControllers();
        final controller = widget.controller;

        return Scaffold(
          appBar: AppBar(
            titleSpacing: 24,
            toolbarHeight: 76,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MadCalc',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Offline planner cięcia sztang na macOS, Windows i Android',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: IconButton.filledTonal(
                  tooltip: controller.availableUpdate != null
                      ? 'Pobierz aktualizację'
                      : 'Sprawdź aktualizacje',
                  onPressed:
                      controller.isCheckingUpdates || controller.isOpeningUpdate
                      ? null
                      : () {
                          if (controller.availableUpdate != null) {
                            unawaited(_handleOpenUpdate());
                            return;
                          }
                          unawaited(_handleCheckUpdates());
                        },
                  icon:
                      controller.isCheckingUpdates || controller.isOpeningUpdate
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          controller.availableUpdate != null
                              ? Icons.system_update_alt_rounded
                              : Icons.update_rounded,
                        ),
                ),
              ),
            ],
          ),
          body: Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1440),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _HeroPanel(controller: controller),
                      if (controller.availableUpdate != null) ...[
                        const SizedBox(height: 16),
                        _UpdateBanner(
                          update: controller.availableUpdate!,
                          controller: controller,
                          onPrimaryAction: _handleOpenUpdate,
                          onSecondaryAction: _handleCheckUpdates,
                        ),
                      ],
                      const SizedBox(height: 24),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final wide = constraints.maxWidth >= 1120;
                          final leftColumn = _buildLeftColumn(
                            context,
                            controller,
                          );
                          final rightColumn = _buildRightColumn(
                            context,
                            controller,
                          );

                          if (wide) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(flex: 5, child: leftColumn),
                                const SizedBox(width: 24),
                                Expanded(flex: 6, child: rightColumn),
                              ],
                            );
                          }

                          return Column(
                            children: [
                              leftColumn,
                              const SizedBox(height: 24),
                              rightColumn,
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLeftColumn(BuildContext context, MadCalcController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Panel(
          title: controller.isEditingItem ? 'Edytuj element' : 'Dodaj element',
          subtitle: controller.itemHint,
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      focusNode: _itemLengthFocusNode,
                      controller: _itemLengthController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: 'Długość (${controller.unit.label})',
                      ),
                      onChanged: controller.updateItemLengthInput,
                      onSubmitted: (_) {
                        _itemQuantityFocusNode.requestFocus();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      focusNode: _itemQuantityFocusNode,
                      controller: _itemQuantityController,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'Ilość szt.',
                      ),
                      onChanged: controller.updateItemQuantityInput,
                      onSubmitted: (_) => _handleSaveItem(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: _handleSaveItem,
                    icon: Icon(
                      controller.isEditingItem
                          ? Icons.check_rounded
                          : Icons.add_rounded,
                    ),
                    label: Text(controller.itemActionTitle),
                  ),
                  if (controller.isEditingItem) ...[
                    const SizedBox(width: 10),
                    TextButton(
                      onPressed: controller.cancelEditing,
                      child: const Text('Anuluj edycję'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _Panel(
          title: 'Lista elementów',
          subtitle:
              'Każdy wpis przechowujemy lokalnie. Nic nie wymaga internetu.',
          child: controller.items.isEmpty
              ? _EmptyState(
                  icon: Icons.straighten_rounded,
                  title: 'Brak elementów do cięcia',
                  message:
                      'Dodaj pierwszy wymiar i ilość sztuk, a potem wygenerujemy plan.',
                )
              : Column(
                  children: [
                    for (
                      var index = 0;
                      index < controller.items.length;
                      index++
                    ) ...[
                      _ItemRow(
                        item: controller.items[index],
                        controller: controller,
                      ),
                      if (index < controller.items.length - 1)
                        Divider(
                          height: 24,
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildRightColumn(BuildContext context, MadCalcController controller) {
    final result = controller.result;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Panel(
          title: 'Parametry cięcia',
          subtitle:
              'Pracuj w centymetrach albo milimetrach. Wynik liczymy lokalnie, bez internetu.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<MeasurementUnit>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: MeasurementUnit.centimeters,
                    label: Text('Centymetry'),
                    icon: Icon(Icons.straighten_rounded),
                  ),
                  ButtonSegment(
                    value: MeasurementUnit.millimeters,
                    label: Text('Milimetry'),
                    icon: Icon(Icons.architecture_rounded),
                  ),
                ],
                selected: {controller.unit},
                onSelectionChanged: (selection) {
                  controller.switchUnit(selection.first);
                },
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _stockLengthController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Długość sztangi (${controller.unit.label})',
                      ),
                      onChanged: controller.updateStockLengthInput,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _sawThicknessController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Grubość piły (${controller.unit.label})',
                      ),
                      onChanged: controller.updateSawThicknessInput,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed:
                        controller.canGenerate && !controller.isGenerating
                        ? _handleGenerate
                        : null,
                    icon: controller.isGenerating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome_rounded),
                    label: Text(
                      controller.isGenerating
                          ? 'Liczę plan...'
                          : 'Generuj plan',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: controller.loadSampleData,
                    icon: const Icon(Icons.science_rounded),
                    label: const Text('Dane przykładowe'),
                  ),
                  OutlinedButton.icon(
                    onPressed: controller.clearAll,
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: const Text('Wyczyść'),
                  ),
                  OutlinedButton.icon(
                    onPressed: controller.canExport ? _handleExport : null,
                    icon: controller.isExporting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.picture_as_pdf_rounded),
                    label: Text(
                      controller.isExporting ? 'Tworzę PDF...' : 'Zapisz PDF',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: controller.canPrint ? _handlePrint : null,
                    icon: controller.isPrinting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.print_rounded),
                    label: Text(
                      controller.isPrinting ? 'Otwieram druk...' : 'Drukuj',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                controller.generationModeLabel,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (controller.lastExportPath != null) ...[
                const SizedBox(height: 14),
                SelectableText(
                  'Ostatni eksport: ${controller.lastExportPath}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        _Panel(
          title: 'Wynik',
          subtitle: result == null
              ? 'Po wygenerowaniu zobaczysz liczbę sztang, odpad, pełny plan cięcia i lokalną analizę AI.'
              : 'Możesz nazywać sztangi, a lokalny asystent AI od razu opisze jakość planu.',
          child: result == null
              ? const _EmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: 'Brak wygenerowanego planu',
                  message:
                      'Uzupełnij dane po lewej stronie i uruchom generowanie.',
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _MetricTile(
                          label: 'Liczba sztang',
                          value: '${result.barCount}',
                        ),
                        _MetricTile(
                          label: 'Łączny odpad',
                          value: controller.formatLength(result.totalWasteMm),
                        ),
                        _MetricTile(
                          label: 'Wykorzystanie',
                          value:
                              '${controller.formatPercent(result.utilizationPercent)}%',
                        ),
                      ],
                    ),
                    if (controller.localAiAnalysis != null) ...[
                      const SizedBox(height: 18),
                      _AiAnalysisCard(analysis: controller.localAiAnalysis!),
                    ],
                    const SizedBox(height: 18),
                    for (
                      var index = 0;
                      index < result.bars.length;
                      index++
                    ) ...[
                      _BarCard(bar: result.bars[index], controller: controller),
                      if (index < result.bars.length - 1)
                        const SizedBox(height: 14),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: 24),
        _Panel(
          title: 'Historia',
          subtitle:
              'Każde wygenerowane wyliczenie zapisujemy lokalnie. Możesz je później wczytać albo usunąć.',
          child: controller.historyEntries.isEmpty
              ? const _EmptyState(
                  icon: Icons.history_rounded,
                  title: 'Brak zapisanych wyliczeń',
                  message:
                      'Wygeneruj pierwszy plan, a pojawi się tutaj w historii lokalnej.',
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: controller.clearHistory,
                        icon: const Icon(Icons.delete_sweep_rounded),
                        label: const Text('Wyczyść historię'),
                      ),
                    ),
                    const SizedBox(height: 14),
                    for (
                      var index = 0;
                      index < controller.historyEntries.length;
                      index++
                    ) ...[
                      _HistoryEntryRow(
                        entry: controller.historyEntries[index],
                        controller: controller,
                      ),
                      if (index < controller.historyEntries.length - 1)
                        Divider(
                          height: 24,
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  void _syncControllers() {
    _syncController(_itemLengthController, widget.controller.itemLengthInput);
    _syncController(
      _itemQuantityController,
      widget.controller.itemQuantityInput,
    );
    _syncController(_stockLengthController, widget.controller.stockLengthInput);
    _syncController(
      _sawThicknessController,
      widget.controller.sawThicknessInput,
    );
  }

  void _syncController(TextEditingController textController, String value) {
    if (textController.text == value) {
      return;
    }

    textController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  void _handleSaveItem() {
    final message = widget.controller.saveCurrentItem();
    if (message != null) {
      _showMessage(message, isError: true);
      return;
    }

    _itemLengthFocusNode.requestFocus();
  }

  Future<void> _handleGenerate() async {
    final message = await widget.controller.generatePlan();
    if (!mounted || message == null) {
      return;
    }
    _showMessage(message, isError: true);
  }

  Future<void> _handleExport() async {
    final message = await widget.controller.exportPdf();
    if (!mounted || message == null) {
      return;
    }
    _showMessage(message);
  }

  Future<void> _handlePrint() async {
    final message = await widget.controller.printPdf();
    if (!mounted || message == null) {
      return;
    }
    _showMessage(message);
  }

  Future<void> _handleCheckUpdates() async {
    final message = await widget.controller.checkForUpdates();
    if (!mounted || message == null) {
      return;
    }
    _showMessage(message);
  }

  Future<void> _handleOpenUpdate() async {
    final message = await widget.controller.openAvailableUpdate();
    if (!mounted || message == null) {
      return;
    }
    _showMessage(message);
  }

  void _showMessage(String message, {bool isError = false}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError
              ? const Color(0xFF8C2F39)
              : const Color(0xFF2C5A44),
        ),
      );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({required this.controller});

  final MadCalcController controller;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [Color(0xFF1D4F82), Color(0xFF2C78B4)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.all(28),
      child: DefaultTextStyle(
        style: textTheme.bodyMedium!.copyWith(color: Colors.white),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          runSpacing: 18,
          spacing: 18,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Jedna aplikacja, lokalnie na desktopie i Androidzie',
                    style: textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'MadCalc liczy plan cięcia bez internetu, pozwala nazwać każdą sztangę i sam sprawdza, czy na GitHub Releases czeka nowsza wersja dla macOS, Windows albo Androida.',
                    style: textTheme.titleMedium?.copyWith(
                      color: const Color(0xFFEFF5FB),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _HeroBadge(icon: Icons.cloud_off_rounded, label: 'Offline'),
                _HeroBadge(
                  icon: Icons.psychology_alt_rounded,
                  label: 'AI lokalne',
                ),
                _HeroBadge(icon: Icons.picture_as_pdf_rounded, label: 'PDF'),
                _HeroBadge(
                  icon: Icons.desktop_windows_rounded,
                  label: 'Windows',
                ),
                _HeroBadge(icon: Icons.laptop_mac_rounded, label: 'macOS'),
                _HeroBadge(icon: Icons.android_rounded, label: 'Android'),
                _HeroBadge(
                  icon: Icons.sell_outlined,
                  label: controller.versionBadgeLabel,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroBadge extends StatelessWidget {
  const _HeroBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: Colors.white),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UpdateBanner extends StatelessWidget {
  const _UpdateBanner({
    required this.update,
    required this.controller,
    required this.onPrimaryAction,
    required this.onSecondaryAction,
  });

  final AppUpdateInfo update;
  final MadCalcController controller;
  final Future<void> Function() onPrimaryAction;
  final Future<void> Function() onSecondaryAction;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final notes = _compactReleaseNotes(update.releaseNotes);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      padding: const EdgeInsets.all(20),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        runSpacing: 16,
        spacing: 16,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Dostępna aktualizacja v${update.latestVersion}',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  'Masz v${update.currentVersion}. MadCalc znalazł nowszy build dla ${update.platformLabel}.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onPrimaryContainer,
                    height: 1.35,
                  ),
                ),
                if (notes != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    notes,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onPrimaryContainer.withValues(
                        alpha: 0.88,
                      ),
                      height: 1.4,
                    ),
                  ),
                ],
                if (update.assetName != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Plik: ${update.assetName}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onPrimaryContainer.withValues(
                        alpha: 0.78,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: controller.isOpeningUpdate
                    ? null
                    : () {
                        unawaited(onPrimaryAction());
                      },
                icon: controller.isOpeningUpdate
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_rounded),
                label: Text(update.primaryActionLabel),
              ),
              OutlinedButton.icon(
                onPressed: controller.isCheckingUpdates
                    ? null
                    : () {
                        unawaited(onSecondaryAction());
                      },
                icon: controller.isCheckingUpdates
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
                label: const Text('Sprawdź ponownie'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String? _compactReleaseNotes(String rawNotes) {
    final normalized = rawNotes
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .take(3)
        .toList(growable: false);

    if (normalized.isEmpty) {
      return null;
    }

    return normalized.join('  ');
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 18),
            child,
          ],
        ),
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.controller});

  final CutItem item;
  final MadCalcController controller;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                controller.formatLength(item.lengthMm),
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${item.quantity} szt. • razem ${controller.formatLength(item.totalLengthMm)}',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Edytuj',
          onPressed: () => controller.beginEditing(item),
          icon: const Icon(Icons.edit_outlined),
        ),
        IconButton(
          tooltip: 'Usuń',
          onPressed: () => controller.deleteItem(item),
          icon: const Icon(Icons.delete_outline_rounded),
        ),
      ],
    );
  }
}

class _HistoryEntryRow extends StatelessWidget {
  const _HistoryEntryRow({required this.entry, required this.controller});

  final CalculationHistoryEntry entry;
  final MadCalcController controller;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                controller.formatHistoryTimestamp(entry.savedAt),
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${entry.result.barCount} sztang • ${entry.totalPieces} szt. • sztanga ${controller.formatLength(entry.settings.stockLengthMm)}',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Odpad ${controller.formatLength(entry.result.totalWasteMm)} • wykorzystanie ${controller.formatPercent(entry.result.utilizationPercent)}%',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: () => controller.loadHistoryEntry(entry),
          child: const Text('Wczytaj'),
        ),
        IconButton(
          tooltip: 'Usuń z historii',
          onPressed: () => controller.deleteHistoryEntry(entry),
          icon: const Icon(Icons.delete_outline_rounded),
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      constraints: const BoxConstraints(minWidth: 150),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _AiAnalysisCard extends StatelessWidget {
  const _AiAnalysisCard({required this.analysis});

  final LocalAiAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accentColor = analysis.hasWarnings
        ? const Color(0xFFB46A25)
        : const Color(0xFF2F7A57);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [
            accentColor.withValues(alpha: 0.16),
            colorScheme.surfaceContainerHighest,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.psychology_alt_rounded,
                      size: 18,
                      color: accentColor,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Asystent AI lokalnie',
                      style: TextStyle(
                        color: accentColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              _MetricTile(label: 'Ocena', value: '${analysis.score}/100'),
              _MetricTile(label: 'Status', value: analysis.statusLabel),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            analysis.headline,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            analysis.summary,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          if (analysis.highlights.isNotEmpty) ...[
            const SizedBox(height: 16),
            _AiSection(
              title: 'Mocne strony',
              icon: Icons.check_circle_outline_rounded,
              items: analysis.highlights,
              color: const Color(0xFF2F7A57),
            ),
          ],
          if (analysis.warnings.isNotEmpty) ...[
            const SizedBox(height: 16),
            _AiSection(
              title: 'Ryzyka',
              icon: Icons.warning_amber_rounded,
              items: analysis.warnings,
              color: const Color(0xFFB46A25),
            ),
          ],
          if (analysis.suggestions.isNotEmpty) ...[
            const SizedBox(height: 16),
            _AiSection(
              title: 'Podpowiedzi',
              icon: Icons.tips_and_updates_outlined,
              items: analysis.suggestions,
              color: const Color(0xFF1D4F82),
            ),
          ],
        ],
      ),
    );
  }
}

class _AiSection extends StatelessWidget {
  const _AiSection({
    required this.title,
    required this.icon,
    required this.items,
    required this.color,
  });

  final String title;
  final IconData icon;
  final List<String> items;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (final item in items)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Icon(Icons.circle, size: 8, color: color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(height: 1.4),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _BarCard extends StatelessWidget {
  const _BarCard({required this.bar, required this.controller});

  final BarPlan bar;
  final MadCalcController controller;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BarNameField(
              bar: bar,
              onChanged: (value) => controller.renameBar(bar.id, value),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _MetricTile(label: 'Elementów', value: '${bar.cutCount}'),
                _MetricTile(
                  label: 'Suma elementów',
                  value: controller.formatLength(bar.totalCutsLengthMm),
                ),
                _MetricTile(
                  label: 'Użycie',
                  value: controller.formatLength(bar.usedLengthMm),
                ),
                _MetricTile(
                  label: 'Odpad',
                  value: controller.formatLength(bar.wasteMm),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Cięcia',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.all(14),
              child: SelectableText(
                bar.cutsMm.map(controller.formatLength).join('  •  '),
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(height: 1.5),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Łączna grubość piły: ${controller.formatLength(controller.totalSawThickness(bar))}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BarNameField extends StatefulWidget {
  const BarNameField({required this.bar, required this.onChanged, super.key});

  final BarPlan bar;
  final ValueChanged<String> onChanged;

  @override
  State<BarNameField> createState() => _BarNameFieldState();
}

class _BarNameFieldState extends State<BarNameField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.bar.name);
  }

  @override
  void didUpdateWidget(covariant BarNameField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bar.id != widget.bar.id ||
        oldWidget.bar.name != widget.bar.name) {
      _controller.value = TextEditingValue(
        text: widget.bar.name,
        selection: TextSelection.collapsed(offset: widget.bar.name.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      decoration: InputDecoration(
        labelText: 'Nazwa sztangi ${widget.bar.barIndex}',
        hintText: widget.bar.displayName,
        prefixIcon: const Icon(Icons.label_outline_rounded),
      ),
      onChanged: widget.onChanged,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(icon, size: 38, color: colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
