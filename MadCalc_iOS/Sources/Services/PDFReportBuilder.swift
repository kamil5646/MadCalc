import CoreGraphics
import Foundation
import UIKit

struct PDFReportBuilder {
    func makeTemporaryReportURL(
        items: [CutItem],
        settings: CutSettings,
        result: OptimizationResult,
        unit: MeasurementUnit,
        generatedAt: Date
    ) throws -> URL {
        let reportsDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("MadCalcReports", isDirectory: true)
        try FileManager.default.createDirectory(at: reportsDirectory, withIntermediateDirectories: true)
        try cleanupOldReports(in: reportsDirectory)

        let suffix = String(UUID().uuidString.prefix(6))
        let fileName = "MadCalc-\(Self.fileDateFormatter.string(from: generatedAt))-\(suffix).pdf"
        let url = reportsDirectory.appendingPathComponent(fileName)
        let data = try makePDF(
            items: items,
            settings: settings,
            result: result,
            unit: unit,
            generatedAt: generatedAt
        )

        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try data.write(to: url, options: .atomic)
        return url
    }

    private func makePDF(
        items: [CutItem],
        settings: CutSettings,
        result: OptimizationResult,
        unit: MeasurementUnit,
        generatedAt: Date
    ) throws -> Data {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextCreator as String: "MadCalc",
            kCGPDFContextAuthor as String: "MadCalc",
            kCGPDFContextTitle as String: "Raport cięcia"
        ]

        let renderer = UIGraphicsPDFRenderer(bounds: PDFLayout.pageRect, format: format)
        return renderer.pdfData { context in
            let render = PDFRenderContext(context: context)
            render.beginPage()

            let totalItemCount = items.reduce(0) { $0 + $1.quantity }
            let totalItemsLength = items.reduce(0) { $0 + $1.totalLengthMm }

            render.drawTitle("MadCalc")
            render.drawSubtitle("Raport optymalizacji cięcia sztang")
            render.drawNote("Wygenerowano \(Self.longDateFormatter.string(from: generatedAt))")

            render.drawTable(
                title: "Podsumowanie",
                headers: ["Zakres", "Wartość"],
                rows: [
                    ["Wejście", "Pozycje: \(items.count) | Elementy: \(totalItemCount) | Łączna długość: \(unit.format(totalItemsLength))"],
                    ["Ustawienia", "Sztanga: \(unit.format(settings.stockLengthMm)) | Grubość piły: \(unit.format(settings.sawThicknessMm)) | Jednostka: \(unit.label)"],
                    ["Wynik", "Liczba sztang: \(result.barCount) | Odpad: \(unit.format(result.totalWasteMm)) | Wykorzystanie: \(formatPercent(result.utilizationPercent))%"]
                ],
                columnFractions: [0.18, 0.82],
                alignments: [.left, .left]
            )

            let itemRows = items
                .sorted(by: { $0.lengthMm > $1.lengthMm })
                .map { item in
                    [
                        unit.format(item.lengthMm),
                        "\(item.quantity)",
                        unit.format(item.totalLengthMm)
                    ]
                }

            render.drawTable(
                title: "Lista elementów",
                headers: ["Długość", "Ilość", "Razem"],
                rows: itemRows,
                columnFractions: [0.36, 0.16, 0.48],
                alignments: [.right, .center, .right]
            )

            var barRows: [[String]] = []
            for bar in result.bars {
                let cutLines = chunkedCuts(bar.cutsMm.map { unit.format($0) }, maxCharactersPerLine: 42)
                for (index, cutLine) in cutLines.enumerated() {
                    if index == 0 {
                        barRows.append([
                            bar.displayName,
                            cutLine,
                            "\(bar.cutCount)",
                            unit.format(bar.usedLengthMm),
                            unit.format(bar.wasteMm)
                        ])
                    } else {
                        barRows.append([
                            "",
                            cutLine,
                            "",
                            "",
                            "",
                        ])
                    }
                }
            }

            render.drawTable(
                title: "Plan cięcia",
                headers: ["Nazwa", "Cięcia", "Elem.", "Użycie", "Odpad"],
                rows: barRows,
                columnFractions: [0.18, 0.36, 0.10, 0.18, 0.18],
                accent: PDFTheme.brandBlue,
                alignments: [.left, .left, .center, .right, .right]
            )

            render.finish()
        }
    }

    private func cleanupOldReports(in directory: URL) throws {
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        let cutoff = Date().addingTimeInterval(-48 * 60 * 60)
        for file in files where file.pathExtension.lowercased() == "pdf" {
            let values = try file.resourceValues(forKeys: [.contentModificationDateKey])
            if let modifiedAt = values.contentModificationDate, modifiedAt < cutoff {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    private func chunkedCuts(_ cuts: [String], maxCharactersPerLine: Int = 52) -> [String] {
        var lines: [String] = []
        var currentLine = ""

        for cut in cuts {
            let candidate = currentLine.isEmpty ? cut : "\(currentLine), \(cut)"
            if candidate.count <= maxCharactersPerLine || currentLine.isEmpty {
                currentLine = candidate
            } else {
                lines.append(currentLine)
                currentLine = cut
            }
        }

        if !currentLine.isEmpty {
            lines.append(currentLine)
        }
        return lines
    }

    private func formatPercent(_ value: Double) -> String {
        String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
    }

    private static let fileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter
    }()

    private static let longDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private enum PDFLayout {
    static let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
    static let margin: CGFloat = 28
    static let topInset: CGFloat = 48
    static let bottomInset: CGFloat = 26
    static let footerHeight: CGFloat = 18
    static let sectionSpacing: CGFloat = 12
    static let paragraphSpacing: CGFloat = 5
    static let panelSpacing: CGFloat = 8
    static let panelPadding: CGFloat = 10
    static let contentWidth: CGFloat = pageRect.width - (margin * 2)
    static let contentBottomY: CGFloat = pageRect.height - bottomInset - footerHeight
}

private enum PDFTheme {
    static let brandBlue = UIColor(red: 0.13, green: 0.39, blue: 0.74, alpha: 1)
    static let brandBlueDark = UIColor(red: 0.07, green: 0.24, blue: 0.52, alpha: 1)
    static let panelFill = UIColor(red: 0.96, green: 0.97, blue: 0.99, alpha: 1)
    static let panelStroke = UIColor(red: 0.86, green: 0.90, blue: 0.96, alpha: 1)
    static let body = UIColor(red: 0.16, green: 0.19, blue: 0.24, alpha: 1)
    static let secondary = UIColor(red: 0.40, green: 0.44, blue: 0.51, alpha: 1)
}

private final class PDFRenderContext {
    private let context: UIGraphicsPDFRendererContext
    private var pageNumber = 0
    private var y: CGFloat = PDFLayout.topInset

    init(context: UIGraphicsPDFRendererContext) {
        self.context = context
    }

    func beginPage() {
        context.beginPage()
        pageNumber += 1
        y = PDFLayout.topInset
        drawPageChrome()
    }

    func finish() {
        drawFooter()
    }

    func drawTitle(_ text: String) {
        drawText(
            text,
            font: .systemFont(ofSize: 23, weight: .bold),
            color: PDFTheme.brandBlueDark,
            spacingAfter: 2
        )
    }

    func drawSubtitle(_ text: String) {
        drawText(
            text,
            font: .systemFont(ofSize: 13, weight: .semibold),
            color: PDFTheme.body,
            spacingAfter: 4
        )
    }

    func drawNote(_ text: String) {
        drawText(
            text,
            font: .systemFont(ofSize: 9.5, weight: .regular),
            color: PDFTheme.secondary,
            spacingAfter: PDFLayout.sectionSpacing
        )
    }

    func drawSectionHeader(_ title: String) {
        ensureSpace(for: 36)

        if y > PDFLayout.topInset + 4 {
            y += 4
        }

        drawText(
            title,
            font: .systemFont(ofSize: 14.5, weight: .bold),
            color: PDFTheme.brandBlueDark,
            spacingAfter: 6
        )
    }

    func drawBulletLine(_ text: String) {
        drawText(
            "• \(text)",
            font: .systemFont(ofSize: 10.5, weight: .regular),
            color: PDFTheme.body,
            spacingAfter: 3
        )
    }

    func drawPanel(title: String, lines: [String], accent: UIColor = PDFTheme.brandBlueDark) {
        let titleFont = UIFont.systemFont(ofSize: 12.5, weight: .bold)
        let lineFont = UIFont.systemFont(ofSize: 10.25, weight: .regular)
        let innerWidth = PDFLayout.contentWidth - (PDFLayout.panelPadding * 2)
        let lineSpacing: CGFloat = 3
        let panelX = PDFLayout.margin
        let panelWidth = PDFLayout.contentWidth
        var remainingLines = lines.isEmpty ? ["Brak danych."] : lines
        var segmentIndex = 0

        repeat {
            let pageTitle = segmentIndex == 0 ? title : "\(title) (cd.)"
            let titleHeight = measure(text: pageTitle, font: titleFont, width: innerWidth)
            let minimumLineHeight = max(measure(text: " ", font: lineFont, width: innerWidth), 12)
            let minimumPanelHeight = PDFLayout.panelPadding * 2 + titleHeight + 6 + minimumLineHeight

            if y + minimumPanelHeight + PDFLayout.panelSpacing > PDFLayout.contentBottomY, y > PDFLayout.topInset {
                drawFooter()
                beginPage()
            }

            let maxContentHeight = max(0, PDFLayout.contentBottomY - y - PDFLayout.panelSpacing)
            var segmentLines: [String] = []
            var segmentLineHeights: [CGFloat] = []
            var segmentLinesHeight: CGFloat = 0
            let headerHeight = PDFLayout.panelPadding * 2 + titleHeight + 6

            while !remainingLines.isEmpty {
                let nextLine = remainingLines[0]
                let nextHeight = measure(text: nextLine, font: lineFont, width: innerWidth)
                let nextSpacing = segmentLines.isEmpty ? 0 : lineSpacing
                let candidateHeight = headerHeight + segmentLinesHeight + nextSpacing + nextHeight

                if candidateHeight <= maxContentHeight || segmentLines.isEmpty {
                    segmentLines.append(nextLine)
                    segmentLineHeights.append(nextHeight)
                    segmentLinesHeight += nextSpacing + nextHeight
                    remainingLines.removeFirst()
                } else {
                    break
                }
            }

            if segmentLines.isEmpty {
                segmentLines = [remainingLines.removeFirst()]
                segmentLineHeights = [measure(text: segmentLines[0], font: lineFont, width: innerWidth)]
                segmentLinesHeight = segmentLineHeights[0]
            }

            let panelHeight = headerHeight + segmentLinesHeight
            let panelRect = CGRect(x: panelX, y: y, width: panelWidth, height: panelHeight)
            let panelPath = UIBezierPath(roundedRect: panelRect, cornerRadius: 12)
            PDFTheme.panelFill.setFill()
            panelPath.fill()
            PDFTheme.panelStroke.setStroke()
            panelPath.lineWidth = 1
            panelPath.stroke()

            let accentRect = CGRect(x: panelRect.minX, y: panelRect.minY, width: 6, height: panelRect.height)
            accent.setFill()
            UIBezierPath(
                roundedRect: accentRect,
                byRoundingCorners: [.topLeft, .bottomLeft],
                cornerRadii: CGSize(width: 12, height: 12)
            ).fill()

            var cursorY = panelRect.minY + PDFLayout.panelPadding
            drawTextAtCursor(
                pageTitle,
                font: titleFont,
                color: accent,
                x: panelRect.minX + PDFLayout.panelPadding,
                y: &cursorY,
                width: innerWidth,
                spacingAfter: 6
            )

            for line in segmentLines {
                drawTextAtCursor(
                    line,
                    font: lineFont,
                    color: PDFTheme.body,
                    x: panelRect.minX + PDFLayout.panelPadding,
                    y: &cursorY,
                    width: innerWidth,
                    spacingAfter: lineSpacing
                )
            }

            y = panelRect.maxY + PDFLayout.panelSpacing
            segmentIndex += 1
        } while !remainingLines.isEmpty
    }

    func drawTable(
        title: String,
        headers: [String],
        rows: [[String]],
        columnFractions: [CGFloat],
        accent: UIColor = PDFTheme.brandBlueDark,
        alignments: [NSTextAlignment]? = nil
    ) {
        guard !headers.isEmpty, headers.count == columnFractions.count else {
            return
        }

        let titleFont = UIFont.systemFont(ofSize: 13, weight: .bold)
        let headerFont = UIFont.systemFont(ofSize: 9.4, weight: .semibold)
        let cellFont = UIFont.systemFont(ofSize: 9.1, weight: .regular)
        let cellPaddingX: CGFloat = 5
        let cellPaddingY: CGFloat = 4
        let minimumRowHeight: CGFloat = 18
        let titleSpacing: CGFloat = 4
        let bottomSpacing: CGFloat = 10

        let fractionTotal = max(columnFractions.reduce(0, +), 0.0001)
        var columnWidths = columnFractions.map { PDFLayout.contentWidth * ($0 / fractionTotal) }
        let widthDelta = PDFLayout.contentWidth - columnWidths.reduce(0, +)
        if !columnWidths.isEmpty {
            columnWidths[columnWidths.count - 1] += widthDelta
        }
        let resolvedAlignments: [NSTextAlignment] = {
            if let alignments, alignments.count == headers.count {
                return alignments
            }
            return headers.map { _ in .left }
        }()

        var remainingRows = rows.isEmpty
            ? [headers.indices.map { $0 == 0 ? "Brak danych." : "" }]
            : rows.map { row in
                var normalized = Array(row.prefix(headers.count))
                while normalized.count < headers.count {
                    normalized.append("")
                }
                return normalized
            }

        var segmentIndex = 0
        var tableRowIndex = 0

        while !remainingRows.isEmpty {
            let pageTitle = segmentIndex == 0 ? title : "\(title) (cd.)"
            let titleHeight = measure(text: pageTitle, font: titleFont, width: PDFLayout.contentWidth)
            let headerHeight = measureRowHeight(
                cells: headers,
                font: headerFont,
                widths: columnWidths,
                paddingX: cellPaddingX,
                paddingY: cellPaddingY,
                minimumHeight: minimumRowHeight
            )
            let firstRowHeight = measureRowHeight(
                cells: remainingRows[0],
                font: cellFont,
                widths: columnWidths,
                paddingX: cellPaddingX,
                paddingY: cellPaddingY,
                minimumHeight: minimumRowHeight
            )

            if y + titleHeight + titleSpacing + headerHeight + firstRowHeight + bottomSpacing > PDFLayout.contentBottomY,
               y > PDFLayout.topInset {
                drawFooter()
                beginPage()
            }

            drawText(
                pageTitle,
                font: titleFont,
                color: accent,
                spacingAfter: titleSpacing
            )

            drawTableRow(
                cells: headers,
                widths: columnWidths,
                height: headerHeight,
                font: headerFont,
                textColor: .white,
                fillColor: accent,
                alignments: resolvedAlignments,
                paddingX: cellPaddingX,
                paddingY: cellPaddingY
            )

            while !remainingRows.isEmpty {
                let row = remainingRows[0]
                let rowHeight = measureRowHeight(
                    cells: row,
                    font: cellFont,
                    widths: columnWidths,
                    paddingX: cellPaddingX,
                    paddingY: cellPaddingY,
                    minimumHeight: minimumRowHeight
                )

                if y + rowHeight > PDFLayout.contentBottomY {
                    break
                }

                let fillColor = tableRowIndex.isMultiple(of: 2) ? UIColor.white : PDFTheme.panelFill
                drawTableRow(
                    cells: row,
                    widths: columnWidths,
                    height: rowHeight,
                    font: cellFont,
                    textColor: PDFTheme.body,
                    fillColor: fillColor,
                    alignments: resolvedAlignments,
                    paddingX: cellPaddingX,
                    paddingY: cellPaddingY
                )

                remainingRows.removeFirst()
                tableRowIndex += 1
            }

            if remainingRows.isEmpty {
                y += bottomSpacing
            } else {
                drawFooter()
                beginPage()
                segmentIndex += 1
            }
        }
    }

    private func drawText(
        _ text: String,
        font: UIFont,
        color: UIColor,
        x: CGFloat = PDFLayout.margin,
        width: CGFloat = PDFLayout.contentWidth,
        spacingAfter: CGFloat = PDFLayout.paragraphSpacing
    ) {
        let height = measure(text: text, font: font, width: width)
        ensureSpace(for: height + spacingAfter)
        let rect = CGRect(x: x, y: y, width: width, height: height)
        draw(text: text, font: font, color: color, in: rect)
        y = rect.maxY + spacingAfter
    }

    private func drawTextAtCursor(
        _ text: String,
        font: UIFont,
        color: UIColor,
        x: CGFloat,
        y: inout CGFloat,
        width: CGFloat,
        spacingAfter: CGFloat
    ) {
        let height = measure(text: text, font: font, width: width)
        let rect = CGRect(x: x, y: y, width: width, height: height)
        draw(text: text, font: font, color: color, in: rect)
        y = rect.maxY + spacingAfter
    }

    private func drawTableRow(
        cells: [String],
        widths: [CGFloat],
        height: CGFloat,
        font: UIFont,
        textColor: UIColor,
        fillColor: UIColor,
        alignments: [NSTextAlignment],
        paddingX: CGFloat,
        paddingY: CGFloat
    ) {
        let rowRect = CGRect(x: PDFLayout.margin, y: y, width: PDFLayout.contentWidth, height: height)
        fillColor.setFill()
        UIRectFill(rowRect)

        var cellX = rowRect.minX
        for (index, width) in widths.enumerated() {
            let cellRect = CGRect(x: cellX, y: rowRect.minY, width: width, height: height)
            PDFTheme.panelStroke.setStroke()
            let cellPath = UIBezierPath(rect: cellRect)
            cellPath.lineWidth = 0.8
            cellPath.stroke()

            let textRect = cellRect.insetBy(dx: paddingX, dy: paddingY)
            drawCellText(
                index < cells.count ? cells[index] : "",
                font: font,
                color: textColor,
                alignment: index < alignments.count ? alignments[index] : .left,
                in: textRect
            )

            cellX += width
        }

        y = rowRect.maxY
    }

    private func drawCellText(
        _ text: String,
        font: UIFont,
        color: UIColor,
        alignment: NSTextAlignment,
        in rect: CGRect
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.alignment = alignment

        NSString(string: text).draw(
            with: rect,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ],
            context: nil
        )
    }

    private func draw(text: String, font: UIFont, color: UIColor, in rect: CGRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.alignment = .left

        NSString(string: text).draw(
            with: rect,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ],
            context: nil
        )
    }

    private func measureRowHeight(
        cells: [String],
        font: UIFont,
        widths: [CGFloat],
        paddingX: CGFloat,
        paddingY: CGFloat,
        minimumHeight: CGFloat
    ) -> CGFloat {
        let cellHeights = zip(cells, widths).map { cell, width in
            measure(text: cell, font: font, width: max(1, width - paddingX * 2))
        }
        let maxHeight = cellHeights.max() ?? 0
        return max(minimumHeight, maxHeight + paddingY * 2)
    }

    private func measure(text: String, font: UIFont, width: CGFloat) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let rect = NSString(string: text).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [
                .font: font,
                .paragraphStyle: paragraph
            ],
            context: nil
        )
        return ceil(rect.height)
    }

    private func ensureSpace(for requiredHeight: CGFloat) {
        if y + requiredHeight > PDFLayout.contentBottomY {
            drawFooter()
            beginPage()
        }
    }

    private func drawPageChrome() {
        let headerRect = CGRect(x: PDFLayout.margin, y: 22, width: PDFLayout.contentWidth, height: 22)
        let headerAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .bold),
            .foregroundColor: PDFTheme.brandBlueDark
        ]
        NSString(string: "MadCalc").draw(in: headerRect, withAttributes: headerAttributes)

        let linePath = UIBezierPath()
        linePath.move(to: CGPoint(x: PDFLayout.margin, y: 48))
        linePath.addLine(to: CGPoint(x: PDFLayout.pageRect.width - PDFLayout.margin, y: 48))
        PDFTheme.panelStroke.setStroke()
        linePath.lineWidth = 1
        linePath.stroke()
    }

    private func drawFooter() {
        let footerRect = CGRect(
            x: PDFLayout.margin,
            y: PDFLayout.pageRect.height - PDFLayout.bottomInset,
            width: PDFLayout.contentWidth,
            height: 14
        )
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8.5, weight: .regular),
            .foregroundColor: PDFTheme.secondary
        ]

        NSString(string: "Strona \(pageNumber)").draw(
            in: footerRect,
            withAttributes: attributes
        )
    }
}
