import Foundation
import SwiftUI

@MainActor
final class MadCalcViewModel: ObservableObject {
  @Published var unit: MeasurementUnit = .centimeters
  @Published var itemLengthInput = ""
  @Published var itemQuantityInput = "1"
  @Published var stockLengthInput = "600"
  @Published var sawThicknessInput = "0,3"
  @Published private(set) var items: [CutItem] = []
  @Published private(set) var result: OptimizationResult?
  @Published private(set) var generatedSettings: CutSettings?
  @Published private(set) var generatedAt: Date?
  @Published private(set) var isGenerating = false
  @Published private(set) var isExporting = false
  @Published var alertState: AlertState?
  @Published var shareFile: ShareFile?

  private let optimizer = CutOptimizer()
  private let persistence = StatePersistence()
  private var editingItemID: UUID?

  init() {
    if let persisted = persistence.load() {
      unit = persisted.unit
      items = persisted.items
      stockLengthInput = unit.format(persisted.stockLengthMm, includeUnit: false)
      sawThicknessInput = unit.format(persisted.sawThicknessMm, includeUnit: false)
      result = persisted.result
      generatedSettings = persisted.generatedSettings
      generatedAt = persisted.generatedAt
    }
  }

  var isEditingItem: Bool {
    editingItemID != nil
  }

  var itemActionTitle: String {
    isEditingItem ? "Zapisz element" : "Dodaj element"
  }

  var itemHint: String {
    switch unit {
    case .centimeters:
      "Domyślnie pracujesz w centymetrach."
    case .millimeters:
      "Pracujesz w milimetrach."
    }
  }

  var canGenerate: Bool {
    !items.isEmpty && !isGenerating && readSettings(showErrors: false) != nil
  }

  var canExport: Bool {
    result != nil && generatedSettings != nil && generatedAt != nil && !isGenerating && !isExporting
  }

  func bindingForUnit() -> Binding<MeasurementUnit> {
    Binding(
      get: { self.unit },
      set: { self.switchUnit(to: $0) }
    )
  }

  func bindingForBarName(_ bar: BarPlan) -> Binding<String> {
    Binding(
      get: {
        self.result?.bars.first(where: { $0.id == bar.id })?.name ?? bar.name
      },
      set: { newValue in
        self.renameBar(barID: bar.id, to: newValue)
      }
    )
  }

  func saveCurrentItem() {
    guard let lengthMm = unit.parse(itemLengthInput), lengthMm > 0 else {
      presentError("Podaj dodatnią długość elementu.")
      return
    }
    guard let quantity = Int(itemQuantityInput), quantity > 0 else {
      presentError("Podaj ilość sztuk większą od zera.")
      return
    }

    let item = CutItem(id: editingItemID ?? UUID(), lengthMm: lengthMm, quantity: quantity)
    if let editingItemID {
      items = items.map { $0.id == editingItemID ? item : $0 }
    } else {
      items.append(item)
    }

    cancelEditing()
    invalidateGeneratedResult()
    persist()
  }

  func beginEditing(_ item: CutItem) {
    editingItemID = item.id
    itemLengthInput = unit.format(item.lengthMm, includeUnit: false)
    itemQuantityInput = "\(item.quantity)"
  }

  func cancelEditing() {
    editingItemID = nil
    itemLengthInput = ""
    itemQuantityInput = "1"
  }

  func deleteItem(_ item: CutItem) {
    items.removeAll { $0.id == item.id }
    if editingItemID == item.id {
      cancelEditing()
    }
    invalidateGeneratedResult()
    persist()
  }

  func switchUnit(to nextUnit: MeasurementUnit) {
    guard nextUnit != unit else {
      return
    }

    itemLengthInput = convertDisplayedValue(itemLengthInput, from: unit, to: nextUnit)
    stockLengthInput = convertDisplayedValue(stockLengthInput, from: unit, to: nextUnit)
    sawThicknessInput = convertDisplayedValue(sawThicknessInput, from: unit, to: nextUnit)
    unit = nextUnit
    persist()
  }

  func settingsDidChange() {
    invalidateGeneratedResult()
    persist()
  }

  func clearAll() {
    items = []
    unit = .centimeters
    itemLengthInput = ""
    itemQuantityInput = "1"
    stockLengthInput = "600"
    sawThicknessInput = "0,3"
    generatedSettings = nil
    generatedAt = nil
    result = nil
    editingItemID = nil
    persist()
  }

  func loadSampleData() {
    items = [
      CutItem(lengthMm: 1200, quantity: 4),
      CutItem(lengthMm: 960, quantity: 3),
      CutItem(lengthMm: 450, quantity: 5),
    ]
    unit = .centimeters
    stockLengthInput = "600"
    sawThicknessInput = "0,3"
    invalidateGeneratedResult()
    persist()
  }

  func generatePlan() {
    guard let settings = readSettings(showErrors: true) else {
      return
    }
    guard !items.isEmpty else {
      presentError("Dodaj przynajmniej jeden element do cięcia.")
      return
    }

    let snapshotItems = items
    let existingBarNames = Dictionary(
      uniqueKeysWithValues: (result?.bars ?? []).map { ($0.barIndex, $0.name) }
    )
    let optimizer = self.optimizer
    isGenerating = true

    Task {
      do {
        let optimized = try await Task.detached(priority: .userInitiated) {
          try optimizer.optimize(items: snapshotItems, settings: settings)
        }.value

        let namedBars = optimized.bars.map { bar in
          var updatedBar = bar
          updatedBar.name = existingBarNames[bar.barIndex] ?? bar.name
          return updatedBar
        }

        result = OptimizationResult(
          barCount: optimized.barCount,
          totalWasteMm: optimized.totalWasteMm,
          utilizationPercent: optimized.utilizationPercent,
          bars: namedBars
        )
        generatedSettings = settings
        generatedAt = Date()
        isGenerating = false
        persist()
      } catch {
        isGenerating = false
        presentError(error.localizedDescription)
      }
    }
  }

  func exportPDF() {
    guard let result, let generatedSettings, let generatedAt else {
      presentError("Najpierw wygeneruj plan cięcia.")
      return
    }
    guard !isExporting else {
      return
    }

    let snapshotItems = items
    let snapshotUnit = unit
    isExporting = true

    Task {
      defer {
        isExporting = false
      }

      do {
        let url = try await Task.detached(priority: .userInitiated) {
          try PDFReportBuilder().makeTemporaryReportURL(
            items: snapshotItems,
            settings: generatedSettings,
            result: result,
            unit: snapshotUnit,
            generatedAt: generatedAt
          )
        }.value

        shareFile = ShareFile(url: url)
      } catch {
        presentError(
          error.localizedDescription.isEmpty
            ? "Nie udało się przygotować PDF." : error.localizedDescription)
      }
    }
  }

  func dismissShare() {
    shareFile = nil
  }

  func formatLength(_ valueMm: Int) -> String {
    unit.format(valueMm)
  }

  func formatPercent(_ value: Double) -> String {
    String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
  }

  func totalSawThickness(for bar: BarPlan) -> Int {
    guard let generatedSettings else { return 0 }
    return max(0, bar.cutCount - 1) * generatedSettings.sawThicknessMm
  }

  func displayName(for bar: BarPlan) -> String {
    result?.bars.first(where: { $0.id == bar.id })?.displayName ?? bar.displayName
  }

  private func convertDisplayedValue(
    _ value: String, from sourceUnit: MeasurementUnit, to targetUnit: MeasurementUnit
  ) -> String {
    guard let valueMm = sourceUnit.parse(value) else {
      return value
    }
    return targetUnit.format(valueMm, includeUnit: false)
  }

  private func readSettings(showErrors: Bool) -> CutSettings? {
    guard let stockLengthMm = unit.parse(stockLengthInput), stockLengthMm > 0 else {
      if showErrors {
        presentError("Długość sztangi musi być większa od zera.")
      }
      return nil
    }

    guard let sawThicknessMm = unit.parse(sawThicknessInput), sawThicknessMm >= 0 else {
      if showErrors {
        presentError("Grubość piły nie może być ujemna.")
      }
      return nil
    }

    return CutSettings(stockLengthMm: stockLengthMm, sawThicknessMm: sawThicknessMm)
  }

  private func invalidateGeneratedResult() {
    result = nil
    generatedSettings = nil
    generatedAt = nil
  }

  private func renameBar(barID: Int, to newName: String) {
    guard var result else { return }
    guard let index = result.bars.firstIndex(where: { $0.id == barID }) else { return }

    result.bars[index].name = newName
    self.result = result
    persist()
  }

  private func persist() {
    let settings =
      readSettings(showErrors: false) ?? CutSettings(stockLengthMm: 6000, sawThicknessMm: 3)
    persistence.save(
      PersistedState(
        unit: unit,
        items: items,
        stockLengthMm: settings.stockLengthMm,
        sawThicknessMm: settings.sawThicknessMm,
        result: result,
        generatedSettings: generatedSettings,
        generatedAt: generatedAt
      )
    )
  }

  private func presentError(_ message: String) {
    alertState = AlertState(title: "MadCalc", message: message)
  }
}
