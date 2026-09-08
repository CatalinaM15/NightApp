import Foundation

struct BodyCareStat: Identifiable, Equatable {
    let optionName: String
    let daysSinceLastPicked: Int?
    var id: String { optionName }
}

struct ExperimentWeeklyStat: Identifiable, Equatable {
    let id: UUID
    let name: String
    let completedDays: Int
    let streakDays: Int
}

struct WeeklyStatsSnapshot: Equatable {
    let weekStart: Date
    let weekEnd: Date
    let bodyCare: [BodyCareStat]
    let exerciseCompletedDays: Int
    let hobbiesDone: [String]
    let dailyCareCompletedDays: Int
    let experiments: [ExperimentWeeklyStat]
}

@MainActor
enum WeeklyStatsCalculator {
    static func calculate(
        on date: Date,
        options: [CardOption],
        history: [SlotSelectionHistory],
        routines: [Routine],
        calendar inputCalendar: Calendar = .autoupdatingCurrent
    ) -> WeeklyStatsSnapshot {
        var calendar = inputCalendar
        calendar.firstWeekday = 1
        let today = calendar.startOfDay(for: date)
        let weekdayOffset = max(calendar.component(.weekday, from: today) - 1, 0)
        let weekStart = calendar.date(byAdding: .day, value: -weekdayOffset, to: today) ?? today
        let weekEndExclusive = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? today
        let weekEnd = calendar.date(byAdding: .day, value: -1, to: weekEndExclusive) ?? weekStart

        let bodyOptions = TodayCardsStore.options(for: .bodyCare, in: options)
        let bodyStats = bodyOptions.map { option in
            let latest = history
                .filter {
                    $0.category == RotatingCardCategory.bodyCare.rawValue &&
                    $0.optionName == option.name && $0.date <= today
                }
                .max { $0.date < $1.date }
            let days = latest.flatMap {
                calendar.dateComponents([.day], from: calendar.startOfDay(for: $0.date), to: today).day
            }
            return BodyCareStat(optionName: option.name, daysSinceLastPicked: days)
        }

        let completedThisWeek: (RotatingCardCategory) -> [SlotSelectionHistory] = { category in
            history.filter {
                $0.category == category.rawValue && $0.completedAt != nil &&
                $0.date >= weekStart && $0.date < weekEndExclusive
            }
        }
        let exerciseDays = Set(completedThisWeek(.exercise).map { calendar.startOfDay(for: $0.date) }).count
        let hobbies = Array(Set(completedThisWeek(.hobby).map(\.optionName))).sorted()

        let dailyCare = TodayCardsStore.routine(forSlot: 4, in: routines)
        let dailyDays = dailyCare.map { completedDays(for: $0, from: weekStart, to: weekEndExclusive, calendar: calendar) } ?? 0
        let experiments = routines
            .filter { (5...7).contains($0.cardSlot ?? 0) }
            .sorted { ($0.cardSlot ?? 0) < ($1.cardSlot ?? 0) }
            .map { routine in
                ExperimentWeeklyStat(
                    id: routine.id,
                    name: routine.title,
                    completedDays: completedDays(for: routine, from: weekStart, to: weekEndExclusive, calendar: calendar),
                    streakDays: streak(for: routine, on: today, calendar: calendar)
                )
            }

        return WeeklyStatsSnapshot(
            weekStart: weekStart,
            weekEnd: weekEnd,
            bodyCare: bodyStats,
            exerciseCompletedDays: exerciseDays,
            hobbiesDone: hobbies,
            dailyCareCompletedDays: dailyDays,
            experiments: experiments
        )
    }

    private static func completedDays(
        for routine: Routine,
        from start: Date,
        to end: Date,
        calendar: Calendar
    ) -> Int {
        Set(routine.completions.compactMap { completion -> Date? in
            let day = calendar.startOfDay(for: completion.completedAt)
            return day >= start && day < end ? day : nil
        }).count
    }

    private static func streak(for routine: Routine, on today: Date, calendar: Calendar) -> Int {
        let completed = Set(routine.completions.map { calendar.startOfDay(for: $0.completedAt) })
        var cursor = completed.contains(today)
            ? today
            : calendar.date(byAdding: .day, value: -1, to: today) ?? today
        var result = 0
        while completed.contains(cursor) {
            result += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return result
    }
}
