import Foundation

enum RoutineWeekday: Int, CaseIterable, Identifiable {
    case monday = 0
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday
    case sunday

    var id: Int { rawValue }

    var shortName: String {
        switch self {
        case .monday: "Mon"
        case .tuesday: "Tue"
        case .wednesday: "Wed"
        case .thursday: "Thu"
        case .friday: "Fri"
        case .saturday: "Sat"
        case .sunday: "Sun"
        }
    }

    var bit: Int { 1 << rawValue }

    init?(calendarWeekday: Int) {
        let rawValue = calendarWeekday == 1 ? 6 : calendarWeekday - 2
        self.init(rawValue: rawValue)
    }
}

enum RoutineSchedule {
    static let allDaysMask = RoutineWeekday.allCases.reduce(0) { $0 | $1.bit }

    static func contains(_ weekday: RoutineWeekday, in mask: Int) -> Bool {
        mask & weekday.bit != 0
    }

    static func toggling(_ weekday: RoutineWeekday, in mask: Int) -> Int {
        mask ^ weekday.bit
    }

    static func includes(date: Date, mask: Int, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        guard let weekday = RoutineWeekday(calendarWeekday: calendar.component(.weekday, from: date)) else {
            return true
        }
        return contains(weekday, in: mask)
    }
}
