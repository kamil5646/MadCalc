import Foundation

enum MeasurementUnit: String, CaseIterable, Codable, Identifiable {
    case centimeters
    case millimeters

    var id: String { rawValue }

    var label: String {
        switch self {
        case .centimeters:
            "cm"
        case .millimeters:
            "mm"
        }
    }

    var millimetersPerUnit: Double {
        switch self {
        case .centimeters:
            10
        case .millimeters:
            1
        }
    }

    func parse(_ rawValue: String) -> Int? {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")

        guard !normalized.isEmpty, let value = Double(normalized) else {
            return nil
        }

        return Int((value * millimetersPerUnit).rounded())
    }

    func format(_ valueMm: Int, includeUnit: Bool = true) -> String {
        let value: String

        switch self {
        case .millimeters:
            value = "\(valueMm)"
        case .centimeters:
            let centimeters = Double(valueMm) / millimetersPerUnit
            if valueMm.isMultiple(of: 10) {
                value = String(format: "%.0f", centimeters)
            } else {
                value = String(format: "%.1f", centimeters).replacingOccurrences(of: ".", with: ",")
            }
        }

        return includeUnit ? "\(value) \(label)" : value
    }
}
