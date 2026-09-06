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
        guard routine.scheduledWeekdaysMask != 0 else { return 0 }
        let todayKey = CivilDay(date: today, calendar: calendar).key
        let todayIsCompletedOccurrence = routine.isScheduled(on: today, calendar: calendar)
            && completedDays.contains(todayKey)
        guard var cursor = todayIsCompletedOccurrence
            ? today
            : previousScheduledDay(before: today, for: routine, calendar: calendar) else { return 0 }
        var count = 0

        while true {
            let key = CivilDay(date: cursor, calendar: calendar).key
            guard key >= routine.activePeriodStartedDayKey, completedDays.contains(key) else { break }
            count += 1
            guard let previous = previousScheduledDay(before: cursor, for: routine, calendar: calendar) else { break }
            cursor = previous
        }
        return count
    }

    private static func previousScheduledDay(
        before date: Date,
        for routine: Routine,
        calendar: Calendar
    ) -> Date? {
        var cursor = date
        for _ in 0..<7 {
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { return nil }
            if routine.isScheduled(on: previous, calendar: calendar) { return previous }
            cursor = previous
        }
        return nil
    }
}
