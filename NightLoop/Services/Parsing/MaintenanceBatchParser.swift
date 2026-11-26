import Foundation

struct MaintenanceBatchEntry: Equatable {
    var title: String
    var frequency: MaintenanceFrequency
    var weekday: Int?

    var scheduleTitle: String {
        if frequency == .weekly, let weekday, let day = RoutineWeekday(rawValue: weekday) {
            return "Weekly · \(day.fullName)"
        }
        return frequency.title
    }
}

enum MaintenanceBatchError: LocalizedError {
    case unknownHeading(line: Int, heading: String)
    case invalidSchedule(line: Int)

    var errorDescription: String? {
        switch self {
        case let .unknownHeading(line, heading): "Line \(line): ‘\(heading)’ is not a supported day or frequency."
        case let .invalidSchedule(line): "Line \(line): choose a valid schedule. Weekly entries need a weekday and are only available for chores."
        }
    }
}

enum MaintenanceBatchParser {
    static func parse(
        _ text: String, kind: MaintenanceKind, defaultFrequency: MaintenanceFrequency, defaultWeekday: Int?
    ) throws -> [MaintenanceBatchEntry] {
        var frequency = defaultFrequency
        var weekday = defaultFrequency == .weekly ? defaultWeekday : nil
        var entries: [MaintenanceBatchEntry] = []
        for (index, rawLine) in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: .newlines).enumerated() {
            var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let bullet = ["- ", "* ", "• "].first { line.hasPrefix($0) }
            if let bullet { line = String(line.dropFirst(bullet.count)).trimmingCharacters(in: .whitespacesAndNewlines) }
            guard !line.isEmpty else { continue }
            if bullet == nil {
                let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                let heading = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
                if let day = day(named: heading) {
                    frequency = .weekly
                    weekday = day.rawValue
                    guard kind == .chores else { throw MaintenanceBatchError.invalidSchedule(line: index + 1) }
                    line = parts.count == 2 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
                } else if let matched = Self.frequency(named: heading) {
                    frequency = matched
                    weekday = matched == .weekly ? defaultWeekday : nil
                    guard kind.frequencies.contains(matched) else { throw MaintenanceBatchError.invalidSchedule(line: index + 1) }
                    line = parts.count == 2 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
                } else if line.hasSuffix(":") {
                    throw MaintenanceBatchError.unknownHeading(line: index + 1, heading: heading)
                }
            }
            guard !line.isEmpty else { continue }
            guard kind.frequencies.contains(frequency),
                  frequency != .weekly || weekday.flatMap(RoutineWeekday.init(rawValue:)) != nil else {
                throw MaintenanceBatchError.invalidSchedule(line: index + 1)
            }
            entries.append(MaintenanceBatchEntry(title: line, frequency: frequency, weekday: weekday))
        }
        return entries
    }

    static func template(for kind: MaintenanceKind) -> String {
        let days = kind == .chores ? RoutineWeekday.allCases.map(\.fullName) : []
        let frequencies = kind.frequencies.filter { $0 != .weekly }.map(\.title)
        return (days + frequencies).map { "\($0):\n" }.joined(separator: "\n")
    }

    private static func day(named name: String) -> RoutineWeekday? {
        let english = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
        let normalized = name.lowercased()
        return RoutineWeekday.allCases.first {
            [english[$0.rawValue], $0.shortName.lowercased(), $0.fullName.lowercased()].contains(normalized)
        }
    }

    private static func frequency(named name: String) -> MaintenanceFrequency? {
        let normalized = name.lowercased()
        if normalized == "annual" { return .yearly }
        return MaintenanceFrequency.allCases.first {
            $0.title.lowercased() == normalized || $0.rawValue.lowercased() == normalized
        }
    }
}
