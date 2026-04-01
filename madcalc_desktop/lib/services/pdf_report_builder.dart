import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/cut_item.dart';
import '../models/cut_settings.dart';
import '../models/measurement_unit.dart';
import '../models/optimization_result.dart';

class PdfReportBuilder {
  static const int _maxPdfPages = 1000;

  Future<Uint8List> build({
    required List<CutItem> items,
    required CutSettings settings,
    required OptimizationResult result,
    required MeasurementUnit unit,
    required DateTime generatedAt,
  }) async {
    final document = pw.Document(
      title: 'MadCalc',
      author: 'MadCalc',
      creator: 'MadCalc',
      subject: 'Raport optymalizacji cięcia',
    );

    final totalItemCount = items.fold<int>(
      0,
      (sum, item) => sum + item.quantity,
    );
    final totalItemsLength = items.fold<int>(
      0,
      (sum, item) => sum + item.totalLengthMm,
    );

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        maxPages: _maxPdfPages,
        margin: const pw.EdgeInsets.fromLTRB(24, 28, 24, 24),
        build: (context) {
          final sortedItems = [...items]
            ..sort((left, right) => right.lengthMm.compareTo(left.lengthMm));

          return [
            pw.Text(
              'MadCalc',
              style: pw.TextStyle(
                fontSize: 24,
                fontWeight: pw.FontWeight.bold,
                color: PdfColor.fromHex('#1F5C99'),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Raport optymalizacji cięcia sztang',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              'Wygenerowano ${_formatDate(generatedAt)}',
              style: const pw.TextStyle(
                fontSize: 9,
                color: PdfColors.blueGrey700,
              ),
            ),
            pw.SizedBox(height: 14),
            ..._buildTableSections(
              title: 'Podsumowanie',
              headers: const ['Zakres', 'Wartość'],
              rows: [
                [
                  'Wejście',
                  'Pozycje: ${items.length} | Elementy: $totalItemCount | Łączna długość: ${unit.format(totalItemsLength)}',
                ],
                [
                  'Ustawienia',
                  'Sztanga: ${unit.format(settings.stockLengthMm)} | Grubość piły: ${unit.format(settings.sawThicknessMm)} | Jednostka: ${unit.label}',
                ],
                [
                  'Wynik',
                  'Liczba sztang: ${result.barCount} | Odpad: ${unit.format(result.totalWasteMm)} | Wykorzystanie: ${_formatPercent(result.utilizationPercent)}%',
                ],
              ],
              columnFlex: const [2, 8],
              alignments: const [
                pw.Alignment.centerLeft,
                pw.Alignment.centerLeft,
              ],
              rowsPerChunk: 12,
            ),
            pw.SizedBox(height: 12),
            ..._buildTableSections(
              title: 'Lista elementów',
              headers: const ['Długość', 'Ilość', 'Razem'],
              rows: sortedItems
                  .map(
                    (item) => [
                      unit.format(item.lengthMm),
                      '${item.quantity}',
                      unit.format(item.totalLengthMm),
                    ],
                  )
                  .toList(),
              columnFlex: const [3, 2, 3],
              alignments: const [
                pw.Alignment.centerRight,
                pw.Alignment.center,
                pw.Alignment.centerRight,
              ],
              rowsPerChunk: 28,
            ),
            pw.SizedBox(height: 12),
            ..._buildTableSections(
              title: 'Plan cięcia',
              headers: const ['Nazwa', 'Cięcia', 'Elem.', 'Użycie', 'Odpad'],
              rows: _buildBarRows(result: result, unit: unit),
              columnFlex: const [2, 5, 1, 2, 2],
              alignments: const [
                pw.Alignment.centerLeft,
                pw.Alignment.centerLeft,
                pw.Alignment.center,
                pw.Alignment.centerRight,
                pw.Alignment.centerRight,
              ],
              rowsPerChunk: 18,
            ),
          ];
        },
      ),
    );

    return document.save();
  }

  List<List<String>> _buildBarRows({
    required OptimizationResult result,
    required MeasurementUnit unit,
  }) {
    final rows = <List<String>>[];
    for (final bar in result.bars) {
      final lines = _chunkCuts(
        bar.cutsMm.map(unit.format).toList(),
        maxCharactersPerLine: 46,
      );
      for (var index = 0; index < lines.length; index++) {
        rows.add([
          index == 0 ? bar.displayName : '',
          lines[index],
          index == 0 ? '${bar.cutCount}' : '',
          index == 0 ? unit.format(bar.usedLengthMm) : '',
          index == 0 ? unit.format(bar.wasteMm) : '',
        ]);
      }
    }
    return rows;
  }

  List<String> _chunkCuts(
    List<String> cuts, {
    required int maxCharactersPerLine,
  }) {
    final lines = <String>[];
    var currentLine = '';
    for (final cut in cuts) {
      final candidate = currentLine.isEmpty ? cut : '$currentLine, $cut';
      if (candidate.length <= maxCharactersPerLine || currentLine.isEmpty) {
        currentLine = candidate;
      } else {
        lines.add(currentLine);
        currentLine = cut;
      }
    }
    if (currentLine.isNotEmpty) {
      lines.add(currentLine);
    }
    return lines;
  }

  List<pw.Widget> _buildTableSections({
    required String title,
    required List<String> headers,
    required List<List<String>> rows,
    required List<double> columnFlex,
    required List<pw.Alignment> alignments,
    required int rowsPerChunk,
  }) {
    final widths = <int, pw.TableColumnWidth>{
      for (var index = 0; index < columnFlex.length; index++)
        index: pw.FlexColumnWidth(columnFlex[index]),
    };
    final normalizedRows =
        (rows.isEmpty
                ? <List<String>>[
                    [
                      'Brak danych.',
                      ...List<String>.filled(headers.length - 1, ''),
                    ],
                  ]
                : rows)
            .map((row) {
              final normalized = [...row];
              while (normalized.length < headers.length) {
                normalized.add('');
              }
              return normalized;
            })
            .toList();
    final widgets = <pw.Widget>[];
    final chunkSize = rowsPerChunk < 1 ? 1 : rowsPerChunk;

    for (var start = 0; start < normalizedRows.length; start += chunkSize) {
      final end = (start + chunkSize).clamp(0, normalizedRows.length);
      final chunk = normalizedRows.sublist(start, end);
      final chunkTitle = start == 0 ? title : '$title (cd.)';

      widgets.add(
        pw.Text(
          chunkTitle,
          style: pw.TextStyle(
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
            color: PdfColor.fromHex('#17395E'),
          ),
        ),
      );
      widgets.add(pw.SizedBox(height: 6));
      widgets.add(
        pw.Table(
          columnWidths: widths,
          border: pw.TableBorder.all(
            color: PdfColor.fromHex('#D7DCE4'),
            width: 0.5,
          ),
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(color: PdfColor.fromHex('#E8EFF7')),
              children: [
                for (var index = 0; index < headers.length; index++)
                  _buildTableCell(
                    headers[index],
                    alignment: alignments[index],
                    isHeader: true,
                  ),
              ],
            ),
            for (final row in chunk)
              pw.TableRow(
                children: [
                  for (var index = 0; index < row.length; index++)
                    _buildTableCell(row[index], alignment: alignments[index]),
                ],
              ),
          ],
        ),
      );

      if (end < normalizedRows.length) {
        widgets.add(pw.SizedBox(height: 10));
      }
    }

    return widgets;
  }

  pw.Widget _buildTableCell(
    String text, {
    required pw.Alignment alignment,
    bool isHeader = false,
  }) {
    return pw.Container(
      alignment: alignment,
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: isHeader ? 8.8 : 8.4,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: isHeader ? PdfColor.fromHex('#17395E') : PdfColors.black,
        ),
      ),
    );
  }

  String _formatDate(DateTime dateTime) {
    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final year = dateTime.year.toString();
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$day.$month.$year, $hour:$minute';
  }

  String _formatPercent(double value) {
    return value.toStringAsFixed(1).replaceAll('.', ',');
  }
}

Future<Uint8List> buildPdfInBackground(Map<String, dynamic> payload) {
  final items = (payload['items'] as List<dynamic>)
      .map((item) => CutItem.fromJson(Map<String, dynamic>.from(item as Map)))
      .toList();
  final settings = CutSettings.fromJson(
    Map<String, dynamic>.from(payload['settings'] as Map),
  );
  final result = OptimizationResult.fromJson(
    Map<String, dynamic>.from(payload['result'] as Map),
  );
  final unit = MeasurementUnit.fromRaw(payload['unit'] as String);
  final generatedAt = DateTime.parse(payload['generatedAt'] as String);

  return PdfReportBuilder().build(
    items: items,
    settings: settings,
    result: result,
    unit: unit,
    generatedAt: generatedAt,
  );
}
