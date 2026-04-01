import Foundation

struct PersistedState: Codable {
    var unit: MeasurementUnit
    var items: [CutItem]
    var stockLengthMm: Int
    var sawThicknessMm: Int
    var result: OptimizationResult?
    var generatedSettings: CutSettings?
    var generatedAt: Date?
}

struct StatePersistence {
    private let defaults: UserDefaults
    private let key = "pl.madmagsystem.madcalc.persistence.v2"
    private let legacyKey = "pl.madmagsystem.madcalc.persistence.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> PersistedState? {
        let data = defaults.data(forKey: key) ?? defaults.data(forKey: legacyKey)
        guard let data else {
            return nil
        }
        return try? JSONDecoder().decode(PersistedState.self, from: data)
    }

    func save(_ state: PersistedState) {
        guard let data = try? JSONEncoder().encode(state) else {
            return
        }
        defaults.set(data, forKey: key)
    }
}
