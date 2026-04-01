import SwiftUI

struct ContentView: View {
  @Environment(\.colorScheme) private var colorScheme
  @ObservedObject var viewModel: MadCalcViewModel

  private var brandBlue: Color { Color(red: 0.13, green: 0.39, blue: 0.74) }
  private var brandBlueDark: Color { Color(red: 0.07, green: 0.24, blue: 0.52) }
  private var brandBlueLight: Color { Color(red: 0.29, green: 0.59, blue: 0.93) }
  private var pageTop: Color {
    colorScheme == .dark
      ? Color(red: 0.07, green: 0.09, blue: 0.12)
      : Color(red: 0.95, green: 0.97, blue: 0.99)
  }
  private var pageBottom: Color { Color(uiColor: .systemGroupedBackground) }
  private var cardBackground: Color { Color(uiColor: .secondarySystemGroupedBackground) }
  private var insetBackground: Color { Color(uiColor: .tertiarySystemGroupedBackground) }
  private var borderColor: Color {
    colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05)
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 18) {
          hero
          itemSection
          settingsSection
          resultSection
        }
        .padding(16)
      }
      .background(backgroundGradient)
      .navigationTitle("MadCalc")
    }
    .tint(brandBlue)
    .sheet(item: $viewModel.shareFile) { shareFile in
      ShareSheet(items: [shareFile.url]) {
        viewModel.dismissShare()
      }
    }
    .alert(item: $viewModel.alertState) { alert in
      Alert(
        title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
    }
  }

  private var hero: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("MadCalc")
        .font(.system(size: 34, weight: .bold, design: .rounded))
        .foregroundStyle(.white)

      Text(
        "Natywna aplikacja iOS do optymalizacji cięcia sztang. Działa offline, zapisuje dane lokalnie i pozwala wyeksportować raport PDF."
      )
      .font(.callout)
      .foregroundStyle(.white.opacity(0.9))

      HStack(spacing: 10) {
        statusCapsule("Offline")
        statusCapsule("SwiftUI")
        statusCapsule("PDF")
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(22)
    .background(
      LinearGradient(
        colors: [brandBlueDark, brandBlue, brandBlueLight],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    )
    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 28, style: .continuous)
        .stroke(Color.white.opacity(0.18), lineWidth: 1)
    )
    .shadow(color: brandBlueDark.opacity(0.14), radius: 18, y: 10)
  }

  private var itemSection: some View {
    sectionCard(title: "Elementy do cięcia", subtitle: viewModel.itemHint) {
      VStack(spacing: 14) {
        HStack(spacing: 12) {
          decimalField("Długość [\(viewModel.unit.label)]", text: $viewModel.itemLengthInput)
          integerField("Ilość szt.", text: $viewModel.itemQuantityInput)
        }

        HStack(spacing: 10) {
          Button(viewModel.itemActionTitle) {
            viewModel.saveCurrentItem()
          }
          .buttonStyle(.borderedProminent)
          .buttonBorderShape(.capsule)

          if viewModel.isEditingItem {
            Button("Anuluj") {
              viewModel.cancelEditing()
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
          }

          Spacer()

          Button("Przykład") {
            viewModel.loadSampleData()
          }
          .buttonStyle(.bordered)
          .buttonBorderShape(.capsule)
        }

        if viewModel.items.isEmpty {
          emptyState("Brak pozycji", "Dodaj pierwszy element do rozkroju.")
        } else {
          VStack(spacing: 10) {
            ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
              itemRow(item: item, index: index + 1)
            }
          }
        }
      }
    }
  }

  private var settingsSection: some View {
    sectionCard(
      title: "Parametry",
      subtitle: "Domyślnie pracujesz w centymetrach, ale możesz przełączyć się na milimetry."
    ) {
      VStack(spacing: 14) {
        Picker("Jednostka", selection: viewModel.bindingForUnit()) {
          ForEach(MeasurementUnit.allCases) { unit in
            Text(unit.label).tag(unit)
          }
        }
        .pickerStyle(.segmented)

        HStack(spacing: 12) {
          decimalField(
            "Długość sztangi [\(viewModel.unit.label)]", text: $viewModel.stockLengthInput
          )
          .onChange(of: viewModel.stockLengthInput) { _ in
            viewModel.settingsDidChange()
          }
          decimalField("Grubość piły [\(viewModel.unit.label)]", text: $viewModel.sawThicknessInput)
            .onChange(of: viewModel.sawThicknessInput) { _ in
              viewModel.settingsDidChange()
            }
        }

        HStack(spacing: 10) {
          Button {
            viewModel.generatePlan()
          } label: {
            if viewModel.isGenerating {
              ProgressView()
                .controlSize(.small)
                .tint(.white)
            } else {
              Text("Generuj plan")
            }
          }
          .buttonStyle(.borderedProminent)
          .buttonBorderShape(.capsule)
          .disabled(!viewModel.canGenerate)

          Button {
            viewModel.exportPDF()
          } label: {
            if viewModel.isExporting {
              ProgressView()
                .controlSize(.small)
            } else {
              Text("Eksportuj PDF")
            }
          }
          .buttonStyle(.bordered)
          .buttonBorderShape(.capsule)
          .disabled(!viewModel.canExport)

          Button("Wyczyść") {
            viewModel.clearAll()
          }
          .buttonStyle(.bordered)
          .buttonBorderShape(.capsule)
        }
      }
    }
  }

  private var resultSection: some View {
    sectionCard(
      title: "Wynik", subtitle: "Nazwij sztangi i wyeksportuj czytelny plan cięcia do PDF."
    ) {
      if let result = viewModel.result, let generatedSettings = viewModel.generatedSettings {
        VStack(alignment: .leading, spacing: 14) {
          LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
            spacing: 12
          ) {
            metricCard("Liczba sztang", value: "\(result.barCount)")
            metricCard("Łączny odpad", value: viewModel.formatLength(result.totalWasteMm))
            metricCard(
              "Wykorzystanie", value: "\(viewModel.formatPercent(result.utilizationPercent))%")
          }

          Text(
            "Policzone dla sztangi \(viewModel.formatLength(generatedSettings.stockLengthMm)) i grubości piły \(viewModel.formatLength(generatedSettings.sawThicknessMm))."
          )
          .font(.footnote)
          .foregroundStyle(.secondary)

          ForEach(result.bars) { bar in
            barCard(bar: bar)
          }
        }
      } else {
        emptyState(
          "Brak wyniku",
          "Dodaj elementy i kliknij „Generuj plan”, aby policzyć liczbę sztang oraz rozpiskę cięć.")
      }
    }
  }

  private var backgroundGradient: some View {
    LinearGradient(
      colors: [pageTop, pageBottom],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
    .ignoresSafeArea()
  }

  private func sectionCard<Content: View>(
    title: String, subtitle: String, @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      VStack(alignment: .leading, spacing: 6) {
        Text(title)
          .font(.title3.weight(.bold))
        Text(subtitle)
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(18)
    .background(cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 24, style: .continuous)
        .stroke(borderColor, lineWidth: 1)
    )
    .shadow(color: Color.black.opacity(0.03), radius: 8, y: 3)
  }

  private func statusCapsule(_ text: String) -> some View {
    Text(text)
      .font(.caption.weight(.semibold))
      .foregroundStyle(.white)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(Color.white.opacity(0.16), in: Capsule())
  }

  private func decimalField(_ title: String, text: Binding<String>) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      TextField(title, text: text)
        .keyboardType(.decimalPad)
        .textFieldStyle(.roundedBorder)
    }
  }

  private func integerField(_ title: String, text: Binding<String>) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      TextField(title, text: text)
        .keyboardType(.numberPad)
        .textFieldStyle(.roundedBorder)
    }
    .frame(maxWidth: 150)
  }

  private func emptyState(_ title: String, _ message: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.headline)
      Text(message)
        .font(.callout)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(18)
    .background(insetBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
  }

  private func metricCard(_ title: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      Text(value)
        .font(.title3.weight(.bold))
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .background(insetBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
  }

  private func itemRow(item: CutItem, index: Int) -> some View {
    HStack(spacing: 12) {
      Text("\(index)")
        .font(.subheadline.weight(.bold))
        .frame(width: 34, height: 34)
        .background(brandBlue.opacity(0.12), in: Circle())
        .foregroundStyle(brandBlueDark)

      VStack(alignment: .leading, spacing: 4) {
        Text(viewModel.formatLength(item.lengthMm))
          .font(.headline)
        Text("\(item.quantity) szt. • razem \(viewModel.formatLength(item.totalLengthMm))")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      Spacer()

      Button("Edytuj") {
        viewModel.beginEditing(item)
      }
      .buttonStyle(.borderless)

      Button("Usuń", role: .destructive) {
        viewModel.deleteItem(item)
      }
      .buttonStyle(.borderless)
    }
    .padding(14)
    .background(insetBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
  }

  private func barCard(bar: BarPlan) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 8) {
          Text("Nazwa sztangi")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

          TextField("Sztanga \(bar.barIndex)", text: viewModel.bindingForBarName(bar))
            .textFieldStyle(.roundedBorder)
            .font(.headline)

          Text(
            "Nr \(bar.barIndex) • \(bar.cutCount) elementów • piła \(viewModel.formatLength(viewModel.totalSawThickness(for: bar)))"
          )
          .font(.footnote)
          .foregroundStyle(.secondary)
        }

        Spacer()

        VStack(alignment: .trailing, spacing: 6) {
          Text("Odpad")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
          Text(viewModel.formatLength(bar.wasteMm))
            .font(.headline.weight(.bold))
            .foregroundStyle(brandBlue)
        }
      }

      VStack(alignment: .leading, spacing: 8) {
        Text("Cięcia")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
        Text(bar.cutsMm.map(viewModel.formatLength).joined(separator: " • "))
          .font(.subheadline)
          .foregroundStyle(.primary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(14)
          .background(cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
      }

      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
        barMeta("Elementów", value: "\(bar.cutCount)")
        barMeta("Suma elementów", value: viewModel.formatLength(bar.totalCutsLengthMm))
        barMeta("Zużycie", value: viewModel.formatLength(bar.usedLengthMm))
        barMeta("Odpad", value: viewModel.formatLength(bar.wasteMm))
      }
    }
    .padding(16)
    .background(insetBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
  }

  private func barMeta(_ label: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(label)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      Text(value)
        .font(.subheadline.weight(.bold))
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
  }
}
