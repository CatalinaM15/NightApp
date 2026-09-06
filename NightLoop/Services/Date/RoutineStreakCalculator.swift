import Foundation

enum RoutineStreakCalculator {
    static func currentStreak(
        for routine: Routine,
        on date: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Int? {
        guard routine.isActive else { return nil }
        let completedDays = Set(routine.completions.map(\.dayKey))
        let today = calendar.startOfDay(for: date)
        let todayKey = CivilDay(date: today, calendar: calendar).key
        var cursor = completedDays.contains(todayKey)
            ? today
            : calendar.date(byAdding: .day, value: -1, to: today) ?? today
        var count = 0

        while true {
            let key = CivilDay(date: cursor, calendar: calendar).key
            guard key >= routine.activePeriodStartedDayKey, completedDays.contains(key) else { break }
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }
}
