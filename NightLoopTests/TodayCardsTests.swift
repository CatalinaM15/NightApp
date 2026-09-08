import Foundation
import SwiftData
import Testing
@testable import NightLoop

@MainActor
@Suite("Today's Cards")
struct TodayCardsTests {
    @Test func bootstrapCreatesDailyCareMigratesThreeGroupedAndDeletesTheRest() throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        for index in 1...5 {
            try RoutineStore.create(
                title: "Group \(index)", iconName: "moon", isGrouped: true,
                steps: [RoutineStepDraft(title: "Step")], in: context
            )
        }
        try RoutineStore.create(title: "Simple", iconName: "moon", in: context)

        try TodayCardsStore.bootstrap(in: context)

        let routines = try context.fetch(FetchDescriptor<Routine>())
        #expect(routines.count == 4)
        #expect(TodayCardsStore.routine(forSlot: 4, in: routines)?.title == "Daily Care")
        #expect(TodayCardsStore.routine(forSlot: 4, in: routines)?.steps.sorted { $0.order < $1.order }.map(\.title) == ["Body Cream", "Skincare"])
        #expect((5...7).compactMap { TodayCardsStore.routine(forSlot: $0, in: routines)?.title } == ["Group 1", "Group 2", "Group 3"])
        #expect(!routines.contains { $0.title == "Group 4" || $0.title == "Group 5" || $0.title == "Simple" })
    }

    @Test func initialRotatingOptionsHaveNoWeekdayDefaults() throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        try TodayCardsStore.bootstrap(in: context)
        let options = try context.fetch(FetchDescriptor<CardOption>())

        #expect(options.count == 12)
        #expect(options.allSatisfy { $0.scheduledWeekdaysMask == 0 })
    }

    @Test func resolvingAConfiguredDefaultCreatesOnlyOneDatedHistoryRecord() throws {
        let (container, monday) = try configuredContainer()
        let context = container.mainContext
        let options = try context.fetch(FetchDescriptor<CardOption>())
        let run = try #require(options.first { $0.name == "Run" })
        try TodayCardsStore.setDefault(option: run, weekday: .monday, selected: true, allOptions: options, in: context)

        let first = try TodayCardsStore.resolveSelection(category: .exercise, on: monday, options: options, history: [], in: context)
        let currentHistory = try context.fetch(FetchDescriptor<SlotSelectionHistory>())
        let second = try TodayCardsStore.resolveSelection(category: .exercise, on: monday, options: options, history: currentHistory, in: context)

        #expect(first?.optionName == "Run")
        #expect(second?.id == first?.id)
        #expect(try context.fetch(FetchDescriptor<SlotSelectionHistory>()).count == 1)
    }

    @Test func anUnassignedWeekdayResolvesToNoSelection() throws {
        let (container, monday) = try configuredContainer()
        let context = container.mainContext
        let options = try context.fetch(FetchDescriptor<CardOption>())
        let selection = try TodayCardsStore.resolveSelection(category: .bodyCare, on: monday, options: options, history: [], in: context)
        #expect(selection == nil)
    }

    @Test func weekdayDefaultBelongsToAtMostOneOptionPerCategory() throws {
        let (container, _) = try configuredContainer()
        let context = container.mainContext
        let options = try context.fetch(FetchDescriptor<CardOption>())
        let run = try #require(options.first { $0.name == "Run" })
        let gym = try #require(options.first { $0.name == "Gym" })
        try TodayCardsStore.setDefault(option: run, weekday: .monday, selected: true, allOptions: options, in: context)
        try TodayCardsStore.setDefault(option: gym, weekday: .monday, selected: true, allOptions: options, in: context)
        #expect(!RoutineSchedule.contains(.monday, in: run.scheduledWeekdaysMask))
        #expect(RoutineSchedule.contains(.monday, in: gym.scheduledWeekdaysMask))
    }

    @Test func editingAnyOptionUpdatesItsNameAndDefaultDays() throws {
        let (container, monday) = try configuredContainer()
        let context = container.mainContext
        let options = try context.fetch(FetchDescriptor<CardOption>())
        let run = try #require(options.first { $0.name == "Run" })
        let selection = try TodayCardsStore.choose(run, category: .exercise, on: monday, history: [], in: context)

        try TodayCardsStore.updateOption(
            run,
            name: "Morning Run",
            scheduledWeekdaysMask: RoutineWeekday.monday.bit | RoutineWeekday.friday.bit,
            allOptions: options,
            history: [selection],
            in: context
        )

        #expect(run.name == "Morning Run")
        #expect(RoutineSchedule.contains(.monday, in: run.scheduledWeekdaysMask))
        #expect(RoutineSchedule.contains(.friday, in: run.scheduledWeekdaysMask))
        #expect(selection.optionName == "Morning Run")
    }

    @Test func customOptionsCanBeAddedToEveryRotatingCategory() throws {
        let (container, _) = try configuredContainer()
        let context = container.mainContext
        var options = try context.fetch(FetchDescriptor<CardOption>())

        try TodayCardsStore.addOption(named: "Face Mask", category: .bodyCare, allOptions: options, in: context)
        options = try context.fetch(FetchDescriptor<CardOption>())
        try TodayCardsStore.addOption(named: "Swim", category: .exercise, allOptions: options, in: context)
        options = try context.fetch(FetchDescriptor<CardOption>())
        try TodayCardsStore.addOption(named: "Music", category: .hobby, allOptions: options, in: context)

        let namesByCategory = Dictionary(grouping: try context.fetch(FetchDescriptor<CardOption>()), by: \.category)
        #expect(namesByCategory[RotatingCardCategory.bodyCare.rawValue]?.contains { $0.name == "Face Mask" } == true)
        #expect(namesByCategory[RotatingCardCategory.exercise.rawValue]?.contains { $0.name == "Swim" } == true)
        #expect(namesByCategory[RotatingCardCategory.hobby.rawValue]?.contains { $0.name == "Music" } == true)
    }

    @Test func datedOverrideDoesNotChangeWeekdayDefaultsAndStartsIncomplete() throws {
        let (container, monday) = try configuredContainer()
        let context = container.mainContext
        let options = try context.fetch(FetchDescriptor<CardOption>())
        let run = try #require(options.first { $0.name == "Run" })
        let gym = try #require(options.first { $0.name == "Gym" })
        try TodayCardsStore.setDefault(option: run, weekday: .monday, selected: true, allOptions: options, in: context)
        let resolved = try #require(try TodayCardsStore.resolveSelection(category: .exercise, on: monday, options: options, history: [], in: context))
        try TodayCardsStore.complete(resolved, in: context)
        let history = try context.fetch(FetchDescriptor<SlotSelectionHistory>())

        let override = try TodayCardsStore.choose(gym, category: .exercise, on: monday, history: history, in: context)
        #expect(override.optionName == "Gym")
        #expect(override.completedAt == nil)
        #expect(RoutineSchedule.contains(.monday, in: run.scheduledWeekdaysMask))
    }

    @Test func rotatingCompletionTogglesWithoutAnUndoWindow() throws {
        let (container, monday) = try configuredContainer()
        let context = container.mainContext
        let run = try #require(try context.fetch(FetchDescriptor<CardOption>()).first { $0.name == "Run" })
        let selection = try TodayCardsStore.choose(run, category: .exercise, on: monday, history: [], in: context)

        try TodayCardsStore.toggleCompletion(selection, at: monday, in: context)
        #expect(selection.completedAt != nil)
        try TodayCardsStore.toggleCompletion(selection, at: monday, in: context)
        #expect(selection.completedAt == nil)
    }

    @Test func archiveCountsDistinctDaysWithAtLeastOneStepCompletion() throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        try TodayCardsStore.bootstrap(in: context)
        try TodayCardsStore.createExperiment(number: 1, title: "Reset", iconName: "sparkles", steps: [RoutineStepDraft(title: "A"), RoutineStepDraft(title: "B")], on: .now, in: context)
        let routine = try #require(TodayCardsStore.routine(forSlot: 5, in: try context.fetch(FetchDescriptor<Routine>())))
        let steps = routine.steps.sorted { $0.order < $1.order }
        let calendar = Calendar(identifier: .gregorian)
        let firstDay = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 20)))
        let secondDay = try #require(calendar.date(byAdding: .day, value: 1, to: firstDay))
        _ = try RoutineGroupCompletionStore.complete(steps[0], in: routine, at: firstDay, calendar: calendar, in: context)
        _ = try RoutineGroupCompletionStore.complete(steps[1], in: routine, at: firstDay, calendar: calendar, in: context)
        _ = try RoutineGroupCompletionStore.complete(steps[0], in: routine, at: secondDay, calendar: calendar, in: context)

        let record = try TodayCardsStore.archiveExperiment(routine, on: secondDay, calendar: calendar, in: context)
        #expect(record.totalActiveDays == 2)
        #expect(TodayCardsStore.routine(forSlot: 5, in: try context.fetch(FetchDescriptor<Routine>())) == nil)
        #expect(try context.fetch(FetchDescriptor<ExperimentArchiveRecord>()).count == 1)
    }

    private func configuredContainer() throws -> (ModelContainer, Date) {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        try TodayCardsStore.bootstrap(in: container.mainContext)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let monday = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: 12)))
        return (container, monday)
    }
}
