import Foundation

struct CalendarSelection: Codable, Equatable {
    var includesAll = true
    var identifiers: Set<String> = []

    init(includesAll: Bool = true, identifiers: Set<String> = []) {
        self.includesAll = includesAll
        self.identifiers = identifiers
    }

    init(storedValue: String) {
        self = storedValue.data(using: .utf8).flatMap { try? JSONDecoder().decode(Self.self, from: $0) } ?? Self()
    }

    var storedValue: String {
        String(data: (try? JSONEncoder().encode(self)) ?? Data(), encoding: .utf8) ?? ""
    }

    func contains(_ identifier: String) -> Bool {
        includesAll || identifiers.contains(identifier)
    }

    func resolvedIdentifiers(available: [String]) -> Set<String> {
        includesAll ? Set(available) : identifiers.intersection(available)
    }

    mutating func toggle(_ identifier: String, available: [String]) {
        identifiers = resolvedIdentifiers(available: available)
        includesAll = false
        if !identifiers.insert(identifier).inserted { identifiers.remove(identifier) }
    }
}
