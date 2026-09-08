import Foundation
import SwiftData
import Testing
@testable import NightLoop

@MainActor
@Suite("Weekly stats")
struct WeeklyStatsTests {
    @Test func categoryStatsUseTheFixedSundayThroughSaturdayWeek() throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        try TodayCardsStore.bootstrap(in: context)
        let calendar = testCalendar
        let today = date(2026, 9, 9, calendar: calendar)
        let sunday = date(2026, 9, 6, calendar: calendar)
        let monday = date(2026, 9, 7, calendar: calendar)
        let tuesday = date(2026, 9, 8, calendar: calendar)

        let body = SlotSelectionHistory(category: .bodyCare, optionName: "Hair Wash", date: monday, calendar: calendar)
        let exerciseOne = SlotSelectionHistory(category: .exercise, optionName: "Run", date: sunday, completedAt: sunday, calendar: calendar)
        let exerciseTwo = SlotSelectionHistory(category: .exercise, optionName: "Gym", date: tuesday, completedAt: tuesday, calendar: calendar)
        let clay = SlotSelectionHistory(category: .hobby, optionName: "Clay", date: monday, completedAt: monday, calendar: calendar)
        let code = SlotSelectionHistory(category: .hobby, optionName: "Code", date: tuesday, completedAt: tuesday, calendar: calendar)
        [body, exerciseOne, exerciseTwo, clay, code].forEach(context.insert)

        let routines = try context.fetch(FetchDescriptor<Routine>())
        let daily = try #require(TodayCardsStore.routine(forSlot: 4, in: routines))
        addParentCompletion(to: daily, date: sunday, calendar: calendar, context: context)
        addParentCompletion(to: daily, date: monday, calendar: calendar, context: context)
        try TodayCardsStore.createExperiment(number: 1, title: "Meditate", iconName: "sparkles", steps: [RoutineStepDraft(title: "Sit")], on: sunday, in: context)
        let updatedRoutines = try context.fetch(FetchDescriptor<Routine>())
        let experiment = try #require(TodayCardsStore.routine(forSlot: 5, in: updatedRoutines))
        for offset in 0...3 {
            addParentCompletion(to: experiment, date: calendar.date(byAdding: .day, value: offset, to: sunday)!, calendar: calendar, context: context)
        }
        try context.save()

        let stats = WeeklyStatsCalculator.calculate(
            on: today,
            options: try context.fetch(FetchDescriptor<CardOption>()),
            history: try context.fetch(FetchDescriptor<SlotSelectionHistory>()),
            routines: try context.fetch(FetchDescriptor<Routine>()),
            calendar: calendar
        )

        #expect(calendar.isDate(stats.weekStart, inSameDayAs: sunday))
        #expect(calendar.isDate(stats.weekEnd, inSameDayAs: date(2026, 9, 12, calendar: calendar)))
        #expect(stats.bodyCare.first { $0.optionName == "Hair Wash" }?.daysSinceLastPicked == 2)
        #expect(stats.exerciseCompletedDays == 2)
        #expect(stats.hobbiesDone == ["Clay", "Code"])
        #expect(stats.dailyCareCompletedDays == 2)
        #expect(stats.experiments.first?.completedDays == 4)
        #expect(stats.experiments.first?.streakDays == 4)
    }

    @Test func incompleteCurrentDayDoesNotBreakExperimentStreak() throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        try TodayCardsStore.bootstrap(in: context)
        let calendar = testCalendar
        let today = date(2026, 9, 10, calendar: calendar)
        try TodayCardsStore.createExperiment(number: 1, title: "Practice", iconName: "sparkles", steps: [RoutineStepDraft(title: "Do")], on: today, in: context)
        let routines = try context.fetch(FetchDescriptor<Routine>())
        let experiment = try #require(TodayCardsStore.routine(forSlot: 5, in: routines))
        for offset in 1...3 {
            addParentCompletion(to: experiment, date: calendar.date(byAdding: .day, value: -offset, to: today)!, calendar: calendar, context: context)
        }
        try context.save()

        let stats = WeeklyStatsCalculator.calculate(on: today, options: [], history: [], routines: routines, calendar: calendar)
        #expect(stats.experiments.first?.streakDays == 3)
    }

    private func addParentCompletion(to routine: Routine, date: Date, calendar: Calendar, context: ModelContext) {
        context.insert(RoutineCompletion(
            dayKey: CivilDay(date: date, calendar: calendar).key,
            completedAt: date,
            timeZoneIdentifier: calendar.timeZone.identifier,
            routine: routine
        ))
    }

    private var testCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }
}
