import Foundation
import SwiftData
import Testing
@testable import NightLoop

@MainActor
@Suite("Linked Daily overview")
struct DailyOverviewTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Bogota")!
        calendar.firstWeekday = 2
        return calendar
    }
    private func date(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: 12))!
    }
    private func daily(in context: ModelContext) throws -> Routine {
        try TodayCardsStore.bootstrap(in: context)
        return try #require(try context.fetch(FetchDescriptor<Routine>()).first { $0.cardSlot == 4 })
    }

    @Test func oldStepsAppearEveryDayAndVariationsFollowTheirWeekday() throws {
        let id = UUID()
        #expect(DailyStepSchedule.includes(id, on: date(23), in: [], calendar: calendar))
        #expect(DailyStepSchedule.includes(id, on: date(24), in: [], calendar: calendar))
        #expect(DailyStepSchedule.variation(for: id, on: date(23), in: [], calendar: calendar) == nil)
        var draft = DailyStepScheduleDraft(weekdaysMask: RoutineWeekday.monday.bit)
        draft.variations[RoutineWeekday.monday.rawValue] = "  Monday treatment "
        let schedule = DailyStepSchedule(stepID: id, draft: draft)
        #expect(DailyStepSchedule.includes(id, on: date(23), in: [schedule], calendar: calendar))
        #expect(!DailyStepSchedule.includes(id, on: date(24), in: [schedule], calendar: calendar))
        #expect(DailyStepSchedule.variation(for: id, on: date(23), in: [schedule], calendar: calendar) == "Monday treatment")
        #expect(DailyStepSchedule.variation(for: id, on: date(24), in: [schedule], calendar: calendar) == nil)
    }

    @Test func editingDailySchedulesPreservesIDsHistoryAndOtherEditorsPreserveSchedules() throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        let routine = try daily(in: context)
        let step = try #require(routine.steps.sorted { $0.order < $1.order }.first)
        _ = try RoutineGroupCompletionStore.complete(step, in: routine, at: date(23), calendar: calendar, in: context)
        let completionID = try #require(step.completions.first?.id)
        var schedule = DailyStepScheduleDraft(weekdaysMask: RoutineWeekday.monday.bit)
        schedule.variations[0] = "  Weekly detail  "
        try RoutineStore.update(routine, title: "Daily", iconName: routine.iconName, steps: [
            RoutineStepDraft(id: step.id, title: "Skincare", carePeriod: .morning, dailySchedule: schedule)
        ], in: context)
        let schedules = try context.fetch(FetchDescriptor<DailyStepSchedule>())
        #expect(schedules.count == 1)
        #expect(schedules.first?.variations[0] == "Weekly detail")
        #expect(step.completions.first?.id == completionID)
        let groups = try context.fetch(FetchDescriptor<DailyCareStepGroup>())
        #expect(DailyCareStepGroup.period(for: step.id, in: groups) == .morning)
        try RoutineStore.update(routine, title: "Daily", iconName: routine.iconName, steps: [RoutineStepDraft(id: step.id, title: "Renamed")], in: context)
        #expect(try context.fetch(FetchDescriptor<DailyStepSchedule>()).first?.weekdaysMask == RoutineWeekday.monday.bit)
        #expect(step.completions.first?.id == completionID)
        try RoutineStore.update(routine, title: "Daily", iconName: routine.iconName, steps: [RoutineStepDraft(title: "New step", carePeriod: .night)], in: context)
        #expect(try context.fetch(FetchDescriptor<DailyStepSchedule>()).isEmpty)
    }

    @Test func invalidScheduleCannotPartiallyModifyTheRoutine() throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        let routine = try daily(in: context)
        let ids = Set(routine.steps.map(\.id))
        #expect(throws: RoutineStoreError.invalidStepSchedule) {
            try RoutineStore.update(routine, title: "Changed", iconName: "other", steps: [
                RoutineStepDraft(title: "Bad step", dailySchedule: DailyStepScheduleDraft(weekdaysMask: 0))
            ], in: context)
        }
        #expect(throws: RoutineStoreError.invalidStepSchedule) {
            try RoutineStore.update(routine, title: "Changed", iconName: "other", steps: [
                RoutineStepDraft(title: "Bad variation", dailySchedule: DailyStepScheduleDraft(variations: []))
            ], in: context)
        }
        #expect(routine.title == "Daily")
        #expect(Set(routine.steps.map(\.id)) == ids)
        #expect(try context.fetch(FetchDescriptor<DailyStepSchedule>()).isEmpty)
    }

    @Test func routineCompletionRequiresOnlyTodaysStepsAndDoesNotIncludeLinkedActivities() throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        let routine = try daily(in: context)
        let steps = routine.steps.sorted { $0.order < $1.order }
        try RoutineStore.update(routine, title: "Daily", iconName: routine.iconName, steps: [
            RoutineStepDraft(id: steps[0].id, title: "Monday", carePeriod: .morning, dailySchedule: DailyStepScheduleDraft(weekdaysMask: RoutineWeekday.monday.bit)),
            RoutineStepDraft(id: steps[1].id, title: "Tuesday", carePeriod: .night, dailySchedule: DailyStepScheduleDraft(weekdaysMask: RoutineWeekday.tuesday.bit))
        ], in: context)
        let skipped = try RoutineGroupCompletionStore.complete(steps[1], in: routine, at: date(23), calendar: calendar, in: context)
        #expect(skipped.stepCompletions.isEmpty)
        let first = try RoutineGroupCompletionStore.complete(steps[0], in: routine, at: date(23), calendar: calendar, in: context)
        #expect(first.parentCompletion != nil)
        #expect(!RoutineGroupCompletionStore.isComplete(steps[1], on: date(23), calendar: calendar))
        let tuesday = try RoutineGroupCompletionStore.completeGroup(routine, at: date(24), calendar: calendar, in: context)
        #expect(tuesday.stepCompletions.count == 1)
        #expect(tuesday.stepCompletions.first?.step?.id == steps[1].id)
        #expect(tuesday.parentCompletion != nil)
        let emptyDay = try RoutineGroupCompletionStore.completeGroup(routine, at: date(25), calendar: calendar, in: context)
        #expect(emptyDay.parentCompletion == nil)
        let option = CardOption(category: .exercise, name: "Gym", sortOrder: 0)
        context.insert(option)
        let activity = try TodayCardsStore.choose(option, category: .exercise, on: date(25), history: [], calendar: calendar, in: context)
        try TodayCardsStore.complete(activity, at: date(25), in: context)
        #expect(try RoutineCompletionStore.completion(for: routine, dayKey: CivilDay(date: date(25), calendar: calendar).key, in: context) == nil)
        let stats = WeeklyStatsCalculator.calculate(on: date(25), options: [option], history: [activity], routines: [routine], calendar: calendar)
        #expect(stats.dailyCareCompletedDays == 2)
        #expect(stats.exerciseCompletedDays == 1)
        try RoutineGroupCompletionStore.uncomplete(steps[0], in: routine, at: date(23), calendar: calendar, in: context)
        #expect(try RoutineCompletionStore.completion(for: routine, dayKey: CivilDay(date: date(23), calendar: calendar).key, in: context) == nil)
    }

    @Test func staleCardQueriesCannotCreateDuplicateSelectionsAndCompletionUsesTheSameRecord() throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        let run = CardOption(category: .exercise, name: "Run", scheduledWeekdaysMask: RoutineWeekday.monday.bit, sortOrder: 0)
        let gym = CardOption(category: .exercise, name: "Gym", sortOrder: 1)
        context.insert(run)
        context.insert(gym)
        try context.save()
        let first = try #require(try TodayCardsStore.resolveSelection(category: .exercise, on: date(23), options: [run, gym], history: [], calendar: calendar, in: context))
        let mirrored = try #require(try TodayCardsStore.resolveSelection(category: .exercise, on: date(23), options: [run, gym], history: [], calendar: calendar, in: context))
        #expect(first.id == mirrored.id)
        try TodayCardsStore.complete(mirrored, at: date(23), in: context)
        #expect(first.completedAt != nil)
        let changed = try TodayCardsStore.choose(gym, category: .exercise, on: date(23), history: [], calendar: calendar, in: context)
        #expect(changed.id == first.id)
        #expect(first.optionName == "Gym")
        #expect(first.completedAt == nil)
        #expect(try context.fetch(FetchDescriptor<SlotSelectionHistory>()).count == 1)
    }

    @Test func dailyChoresMatchTheAssignedDayAndUndoPreservesAllEarlierHistory() throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        let monday = try MaintenanceStore.create(title: "Laundry", kind: .chores, frequency: .weekly, weekday: 0, in: context)
        let tuesday = try MaintenanceStore.create(title: "Kitchen", kind: .chores, frequency: .weekly, weekday: 1, in: context)
        let monthly = try MaintenanceStore.create(title: "Oven", kind: .chores, frequency: .monthly, in: context)
        let doctor = try MaintenanceStore.create(title: "Dentist", kind: .doctorVisits, frequency: .monthly, in: context)
        #expect(MaintenanceStore.chores(on: date(23), among: [monday, tuesday, monthly, doctor], calendar: calendar).map(\.id) == [monday.id])
        let old = try MaintenanceStore.record(monday, on: date(16), now: date(25), calendar: calendar, in: context)
        let oldID = old.id
        let change = try MaintenanceStore.setWeeklyCompletion(true, for: monday, on: date(23), now: date(25), calendar: calendar, in: context)
        #expect(monday.isRecordedThisWeek(on: date(23), calendar: calendar))
        #expect(monday.records.count == 2)
        try MaintenanceStore.undoWeeklyCompletion(change, for: monday, in: context)
        #expect(!monday.isRecordedThisWeek(on: date(23), calendar: calendar))
        #expect(monday.records.map(\.id) == [oldID])
        try MaintenanceStore.record(monday, on: date(23), now: date(25), calendar: calendar, in: context)
        try MaintenanceStore.record(monday, on: date(24), now: date(25), calendar: calendar, in: context)
        let recordedIDs = Set(monday.records.map(\.id))
        let unchecked = try MaintenanceStore.setWeeklyCompletion(false, for: monday, on: date(23), now: date(25), calendar: calendar, in: context)
        #expect(!monday.isRecordedThisWeek(on: date(23), calendar: calendar))
        #expect(monday.records.map(\.id) == [oldID])
        try MaintenanceStore.undoWeeklyCompletion(unchecked, for: monday, in: context)
        #expect(Set(monday.records.map(\.id)) == recordedIDs)
        #expect(monday.isRecordedThisWeek(on: date(23), calendar: calendar))
    }

    @Test func existingExerciseStepsLinkAutomaticallyAndExplicitNoneOverridesTheDefault() {
        let routine = Routine(title: "Daily", isGrouped: true, cardSlot: 4)
        let exercise = NightRoutineStep(title: " exercise ", order: 0, routine: routine)
        #expect(DailyStepActivityLink.category(for: exercise, in: []) == .exercise)
        let disabled = DailyStepActivityLink(stepID: exercise.id, category: nil)
        #expect(DailyStepActivityLink.category(for: exercise, in: [disabled]) == nil)
        let custom = NightRoutineStep(title: "Morning movement", order: 1, routine: routine)
        #expect(DailyStepActivityLink.category(for: custom, in: []) == nil)
        let linked = DailyStepActivityLink(stepID: custom.id, category: .exercise)
        #expect(DailyStepActivityLink.category(for: custom, in: [linked]) == .exercise)
    }

    @Test func explicitLinksPersistAndUseCardCompletionWithoutDuplicatingRoutineCompletion() throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        let routine = try daily(in: context)
        let drafts = [
            RoutineStepDraft(title: "Morning movement", carePeriod: .morning, dailySchedule: DailyStepScheduleDraft(linkedCategory: .exercise)),
            RoutineStepDraft(title: "Skincare", carePeriod: .morning, dailySchedule: DailyStepScheduleDraft())
        ]
        try RoutineStore.update(routine, title: "Daily", iconName: routine.iconName, steps: drafts, in: context)
        let movement = try #require(routine.steps.first { $0.id == drafts[0].id })
        let skincare = try #require(routine.steps.first { $0.id == drafts[1].id })
        var links = try context.fetch(FetchDescriptor<DailyStepActivityLink>())
        #expect(DailyStepActivityLink.category(for: movement, in: links) == .exercise)
        let skipped = try RoutineGroupCompletionStore.complete(movement, in: routine, at: date(23), calendar: calendar, in: context)
        #expect(skipped.stepCompletions.isEmpty)
        let completed = try RoutineGroupCompletionStore.complete(skincare, in: routine, at: date(23), calendar: calendar, in: context)
        #expect(completed.parentCompletion != nil)
        #expect(movement.completions.isEmpty)
        try RoutineStore.update(routine, title: "Daily", iconName: routine.iconName, steps: routine.steps.map {
            RoutineStepDraft(id: $0.id, title: $0.title)
        }, in: context)
        links = try context.fetch(FetchDescriptor<DailyStepActivityLink>())
        #expect(DailyStepActivityLink.category(for: movement, in: links) == .exercise)
        try RoutineStore.update(routine, title: "Daily", iconName: routine.iconName, steps: [drafts[1]], in: context)
        #expect(try context.fetch(FetchDescriptor<DailyStepActivityLink>()).contains { $0.stepID == movement.id } == false)
    }

    @Test func unsupportedCardLinksAreRejectedBeforeSaving() throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        let routine = try daily(in: context)
        let ids = Set(routine.steps.map(\.id))
        #expect(throws: RoutineStoreError.invalidStepLink) {
            try RoutineStore.update(routine, title: "Changed", iconName: "other", steps: [
                RoutineStepDraft(title: "Not supported", dailySchedule: DailyStepScheduleDraft(linkedCategory: .hobby))
            ], in: context)
        }
        #expect(routine.title == "Daily")
        #expect(Set(routine.steps.map(\.id)) == ids)
    }

    @Test func versionEightMigrationKeepsWeekdaysVariationsAndSupportsPersistedUnlinking() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "InlineActivity.store")
        let stepID = UUID()
        var schedule = DailyStepScheduleDraft(weekdaysMask: RoutineWeekday.monday.bit)
        schedule.variations[0] = "Before breakfast"
        do {
            let schema = Schema(versionedSchema: NightLoopSchemaV8.self)
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration("InlineActivity", schema: schema, url: url, cloudKitDatabase: .none))
            let context = container.mainContext
            let routine = Routine(title: "Daily", isGrouped: true, cardSlot: 4)
            context.insert(routine)
            context.insert(NightRoutineStep(id: stepID, title: "Exercise", order: 0, routine: routine))
            context.insert(DailyCareStepGroup(stepID: stepID, period: .morning))
            context.insert(DailyStepSchedule(stepID: stepID, draft: schedule))
            try context.save()
        }
        let schema = Schema(versionedSchema: NightLoopSchemaV9.self)
        let container = try ModelContainer(for: schema, migrationPlan: NightLoopMigrationPlan.self,
                                         configurations: ModelConfiguration("InlineActivity", schema: schema, url: url, cloudKitDatabase: .none))
        let context = container.mainContext
        let routine = try #require(try context.fetch(FetchDescriptor<Routine>()).first)
        let step = try #require(routine.steps.first)
        let storedSchedule = try #require(try context.fetch(FetchDescriptor<DailyStepSchedule>()).first)
        #expect(step.id == stepID)
        #expect(storedSchedule.weekdaysMask == RoutineWeekday.monday.bit)
        #expect(storedSchedule.variations[0] == "Before breakfast")
        #expect(DailyStepActivityLink.category(for: step, in: []) == .exercise)
        try RoutineStore.update(routine, title: "Daily", iconName: routine.iconName, steps: [
            RoutineStepDraft(id: stepID, title: "Exercise", carePeriod: .morning, dailySchedule: schedule)
        ], in: context)
        let fresh = ModelContext(container)
        let links = try fresh.fetch(FetchDescriptor<DailyStepActivityLink>())
        #expect(links.count == 1)
        #expect(DailyStepActivityLink.category(for: step, in: links) == nil)
        #expect(try fresh.fetch(FetchDescriptor<DailyStepSchedule>()).first?.variations[0] == "Before breakfast")
    }

    @Test func fixedExerciseIsCreatedOnlyOnceAndKeepsItsPlaceAndHistory() throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        let routine = try daily(in: context)
        let exercise = try RoutineStore.ensureDailyExercise(routine, on: date(25), in: context)
        #expect(exercise.title == "Exercise")
        let id = exercise.id
        let count = routine.steps.count
        #expect(DailyCareStepGroup.period(for: id, in: try context.fetch(FetchDescriptor<DailyCareStepGroup>())) == .morning)
        let drafts = routine.steps.sorted { $0.order < $1.order }.map {
            RoutineStepDraft(id: $0.id, title: $0.title, carePeriod: $0.id == id ? .night : .morning,
                             dailySchedule: DailyStepScheduleDraft(linkedCategory: $0.id == id ? .exercise : nil))
        }
        try RoutineStore.update(routine, title: "Daily", iconName: routine.iconName, steps: drafts, in: context)
        let again = try RoutineStore.ensureDailyExercise(routine, on: date(25), in: context)
        #expect(again.id == id)
        #expect(routine.steps.count == count)
        #expect(DailyCareStepGroup.period(for: id, in: try context.fetch(FetchDescriptor<DailyCareStepGroup>())) == .night)
    }

    @Test func existingExerciseIsReusedAndOnlyMovingIsAppliedWhileOtherStepsCanBeDeleted() throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        let routine = try daily(in: context)
        let oldStep = routine.steps[0]
        oldStep.title = "Exercise"
        let completion = NightRoutineStepCompletion(date: date(23), step: oldStep, calendar: calendar)
        context.insert(completion)
        try context.save()
        let fixed = try RoutineStore.ensureDailyExercise(routine, on: date(25), in: context)
        #expect(fixed.id == oldStep.id)
        #expect(fixed.completions.first?.id == completion.id)
        try RoutineStore.update(routine, title: "Daily", iconName: routine.iconName, steps: [
            RoutineStepDraft(id: fixed.id, title: "Renamed", carePeriod: .afternoon,
                             dailySchedule: DailyStepScheduleDraft(weekdaysMask: RoutineWeekday.monday.bit))
        ], in: context)
        #expect(routine.steps.count == 1)
        #expect(fixed.title == "Exercise")
        #expect(DailyCareStepGroup.period(for: fixed.id, in: try context.fetch(FetchDescriptor<DailyCareStepGroup>())) == .afternoon)
        #expect(try context.fetch(FetchDescriptor<DailyStepSchedule>()).first { $0.stepID == fixed.id }?.weekdaysMask == RoutineSchedule.allDaysMask)
        #expect(fixed.completions.first?.id == completion.id)
        try RoutineStore.update(routine, title: "Daily", iconName: routine.iconName, steps: [], in: context)
        #expect(routine.steps.count == 1)
        #expect(routine.steps.first?.id == fixed.id)
        #expect(try context.fetch(FetchDescriptor<DailyStepActivityLink>()).first { $0.stepID == fixed.id }?.category == "exercise")
    }

    @Test func fixedExerciseDoesNotDuplicateExistingLinkedStepsOrSwitchIdentityAfterReordering() throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        let routine = try daily(in: context)
        let fixed = try RoutineStore.ensureDailyExercise(routine, on: date(25), in: context)
        let duplicate = NightRoutineStep(title: "Exercise", order: -1, routine: routine)
        context.insert(duplicate)
        try context.save()
        let again = try RoutineStore.ensureDailyExercise(routine, on: date(25), in: context)
        #expect(again.id == fixed.id)
        #expect(routine.steps.contains { $0.id == duplicate.id })
        let links = try context.fetch(FetchDescriptor<DailyStepActivityLink>())
        #expect(DailyStepActivityLink.category(for: duplicate, in: links) == nil)
        #expect(routine.steps.filter { DailyStepActivityLink.category(for: $0, in: links) == .exercise }.count == 1)
    }

    @Test func versionSevenMigrationPreservesExistingDataAndDefaultsStepsToEveryDay() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Daily.store")
        let stepID = UUID()
        let choreID = UUID()
        let selectionID = UUID()
        do {
            let schema = Schema(versionedSchema: NightLoopSchemaV7.self)
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration("Daily", schema: schema, url: url, cloudKitDatabase: .none))
            let context = container.mainContext
            let routine = Routine(title: "Daily Care", isGrouped: true, cardSlot: 4)
            context.insert(routine)
            let step = NightRoutineStep(id: stepID, title: "Skincare", order: 0, routine: routine)
            context.insert(step)
            context.insert(DailyCareStepGroup(stepID: stepID, period: .morning))
            context.insert(NightRoutineStepCompletion(date: date(23), step: step, calendar: calendar))
            let chore = MaintenanceItem(id: choreID, title: "Laundry", kind: .chores, frequency: .weekly, weekday: 0)
            context.insert(chore)
            context.insert(MaintenanceRecord(date: date(23), item: chore))
            context.insert(SlotSelectionHistory(id: selectionID, category: .exercise, optionName: "Gym", date: date(23), completedAt: date(23), calendar: calendar))
            context.insert(DailyNote(date: date(23), text: "Keep note", calendar: calendar))
            try context.save()
        }
        let schema = Schema(versionedSchema: NightLoopSchemaV9.self)
        let container = try ModelContainer(for: schema, migrationPlan: NightLoopMigrationPlan.self,
                                         configurations: ModelConfiguration("Daily", schema: schema, url: url, cloudKitDatabase: .none))
        let context = container.mainContext
        try TodayCardsStore.bootstrap(in: context)
        let routine = try #require(try context.fetch(FetchDescriptor<Routine>()).first { $0.cardSlot == 4 })
        #expect(routine.title == "Daily")
        #expect(routine.steps.first?.id == stepID)
        #expect(routine.steps.first?.completions.count == 1)
        #expect(try context.fetch(FetchDescriptor<DailyCareStepGroup>()).first?.period == "morning")
        #expect(try context.fetch(FetchDescriptor<MaintenanceItem>()).first?.id == choreID)
        #expect(try context.fetch(FetchDescriptor<MaintenanceRecord>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<SlotSelectionHistory>()).first?.id == selectionID)
        #expect(try context.fetch(FetchDescriptor<DailyNote>()).first?.text == "Keep note")
        #expect(try context.fetch(FetchDescriptor<DailyStepSchedule>()).isEmpty)
        #expect(DailyStepSchedule.includes(stepID, on: date(24), in: [], calendar: calendar))
        try RoutineStore.update(routine, title: "Daily", iconName: routine.iconName, steps: [
            RoutineStepDraft(id: stepID, title: "Skincare", dailySchedule: DailyStepScheduleDraft(weekdaysMask: RoutineWeekday.tuesday.bit))
        ], in: context)
        let fresh = ModelContext(container)
        #expect(try fresh.fetch(FetchDescriptor<DailyStepSchedule>()).first?.weekdaysMask == RoutineWeekday.tuesday.bit)
    }
}
