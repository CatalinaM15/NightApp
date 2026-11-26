import Foundation
import SwiftData
import Testing
@testable import NightLoop

@MainActor
@Suite("Daily Care groups")
struct DailyCareTests {
    @Test func changingGroupsPreservesCompletionsAndOtherEditorsPreserveGroups() throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        try TodayCardsStore.bootstrap(in: context)
        let routine = try #require(try context.fetch(FetchDescriptor<Routine>()).first { $0.cardSlot == 4 })
        let steps = routine.steps.sorted { $0.order < $1.order }
        let date = Date.now
        _ = try RoutineGroupCompletionStore.completeGroup(routine, at: date, in: context)
        #expect(DailyCareStepGroup.period(for: steps[0].id, in: []) == .night)

        try RoutineStore.update(routine, title: routine.title, iconName: routine.iconName, steps: [
            RoutineStepDraft(id: steps[0].id, title: " Body Cream ", carePeriod: .morning),
            RoutineStepDraft(id: steps[1].id, title: steps[1].title, carePeriod: .afternoon)
        ], in: context)
        var groups = try context.fetch(FetchDescriptor<DailyCareStepGroup>())
        #expect(DailyCareStepGroup.period(for: steps[0].id, in: groups) == .morning)
        #expect(DailyCareStepGroup.period(for: steps[1].id, in: groups) == .afternoon)
        #expect(steps[0].title == "Body Cream")
        #expect(RoutineGroupCompletionStore.completedStepCount(for: routine, on: date) == 2)
        #expect(routine.completions.count == 1)

        try RoutineStore.update(routine, title: routine.title, iconName: routine.iconName, steps: steps.map {
            RoutineStepDraft(id: $0.id, title: $0.title)
        }, in: context)
        groups = try context.fetch(FetchDescriptor<DailyCareStepGroup>())
        #expect(DailyCareStepGroup.period(for: steps[0].id, in: groups) == .morning)

        try RoutineStore.update(routine, title: routine.title, iconName: routine.iconName, steps: [
            RoutineStepDraft(id: steps[0].id, title: steps[0].title, carePeriod: .night)
        ], in: context)
        groups = try context.fetch(FetchDescriptor<DailyCareStepGroup>())
        #expect(groups.count == 1)
        #expect(DailyCareStepGroup.period(for: steps[0].id, in: groups) == .night)
    }

    @Test func versionFiveMigrationPreservesCareHistoryNotesAndCardSchedules() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Migration.store")
        let stepID = UUID()
        let date = Date.now
        do {
            let schema = Schema(versionedSchema: NightLoopSchemaV5.self)
            let config = ModelConfiguration("Migration", schema: schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: config)
            let context = container.mainContext
            let routine = Routine(title: "Daily Care", isGrouped: true, cardSlot: 4)
            context.insert(routine)
            let step = NightRoutineStep(id: stepID, title: "Skincare", order: 0, routine: routine)
            context.insert(step)
            context.insert(NightRoutineStepCompletion(date: date, step: step))
            context.insert(RoutineCompletion(dayKey: CivilDay(date: date).key, completedAt: date,
                                             timeZoneIdentifier: TimeZone.autoupdatingCurrent.identifier, routine: routine))
            context.insert(DailyNote(date: date, text: "Keep this note"))
            context.insert(CardOption(category: .bodyCare, name: "Hair Wash", scheduledWeekdaysMask: RoutineWeekday.monday.bit, sortOrder: 0))
            try context.save()
        }
        let schema = Schema(versionedSchema: NightLoopSchemaV9.self)
        let config = ModelConfiguration("Migration", schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, migrationPlan: NightLoopMigrationPlan.self, configurations: config)
        let context = container.mainContext
        let step = try #require(try context.fetch(FetchDescriptor<NightRoutineStep>()).first)
        #expect(step.id == stepID)
        #expect(RoutineGroupCompletionStore.isComplete(step, on: date))
        #expect(step.routine?.completions.count == 1)
        #expect(try context.fetch(FetchDescriptor<DailyNote>()).first?.text == "Keep this note")
        #expect(try context.fetch(FetchDescriptor<CardOption>()).first?.scheduledWeekdaysMask == RoutineWeekday.monday.bit)
        #expect(try context.fetch(FetchDescriptor<DailyCareStepGroup>()).isEmpty)
        context.insert(DailyCareStepGroup(stepID: stepID, period: .morning))
        try context.save()
        let freshContext = ModelContext(container)
        let groups = try freshContext.fetch(FetchDescriptor<DailyCareStepGroup>())
        #expect(DailyCareStepGroup.period(for: stepID, in: groups) == .morning)
    }
}
