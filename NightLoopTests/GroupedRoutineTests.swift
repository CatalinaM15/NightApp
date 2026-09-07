import Foundation
import SwiftData
import Testing
@testable import NightLoop

@MainActor
@Suite("Grouped routines")
struct GroupedRoutineTests {
    @Test func creationRequiresAtLeastOneNonEmptyStep() throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let context = container.mainContext

        #expect(throws: RoutineStoreError.groupedRoutineNeedsStep) {
            try RoutineStore.create(title: "Wind down", iconName: "moon.stars", isGrouped: true, in: context)
        }
        #expect(throws: RoutineStoreError.emptyStepTitle) {
            try RoutineStore.create(
                title: "Wind down",
                iconName: "moon.stars",
                isGrouped: true,
                steps: [RoutineStepDraft(title: "   ")],
                in: context
            )
        }
    }

    @Test func groupedStepsAllowDuplicateTitlesAndKeepTheirOrder() throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        try RoutineStore.create(
            title: "Prepare",
            iconName: "moon.stars",
            isGrouped: true,
            steps: [RoutineStepDraft(title: "Check"), RoutineStepDraft(title: "Check")],
            in: context
        )

        let routine = try #require(try context.fetch(FetchDescriptor<Routine>()).first)
        #expect(routine.isGrouped)
        #expect(routine.steps.sorted { $0.order < $1.order }.map(\.title) == ["Check", "Check"])
    }

    @Test func editingReordersRenamesAddsAndDeletesStepsWithoutChangingType() throws {
        let (container, routine, originalSteps) = try makeGroupedRoutine()
        let context = container.mainContext
        let added = RoutineStepDraft(title: "Journal")

        try RoutineStore.update(
            routine,
            title: "Evening reset",
            iconName: routine.iconName,
            steps: [
                RoutineStepDraft(id: originalSteps[1].id, title: "Read slowly"),
                added
            ],
            in: context
        )

        let updated = routine.steps.sorted { $0.order < $1.order }
        #expect(routine.isGrouped)
        #expect(updated.map(\.title) == ["Read slowly", "Journal"])
        #expect(updated.map(\.id) == [originalSteps[1].id, added.id])
        #expect(!updated.contains { $0.id == originalSteps[0].id })
    }

    @Test func completingFinalStepCompletesParentAndUndoRemovesOnlyThatAction() throws {
        let (container, routine, steps) = try makeGroupedRoutine()
        let context = container.mainContext
        let date = Date(timeIntervalSince1970: 1_789_000_000)

        let firstChange = try RoutineGroupCompletionStore.complete(steps[0], in: routine, at: date, in: context)
        #expect(firstChange.parentCompletion == nil)
        let finalChange = try RoutineGroupCompletionStore.complete(steps[1], in: routine, at: date, in: context)
        #expect(finalChange.parentCompletion != nil)
        #expect(RoutineGroupCompletionStore.completedStepCount(for: routine, on: date) == 2)

        try RoutineGroupCompletionStore.undo(finalChange, in: context)
        #expect(RoutineGroupCompletionStore.isComplete(steps[0], on: date))
        #expect(!RoutineGroupCompletionStore.isComplete(steps[1], on: date))
        #expect(try RoutineCompletionStore.completion(for: routine, dayKey: CivilDay(date: date).key, in: context) == nil)
    }

    @Test func completeGroupPreservesEarlierPartialWorkWhenUndone() throws {
        let (container, routine, steps) = try makeGroupedRoutine()
        let context = container.mainContext
        let date = Date(timeIntervalSince1970: 1_789_000_000)
        _ = try RoutineGroupCompletionStore.complete(steps[0], in: routine, at: date, in: context)

        let groupChange = try RoutineGroupCompletionStore.completeGroup(routine, at: date, in: context)
        #expect(groupChange.stepCompletions.count == 1)
        #expect(groupChange.parentCompletion != nil)
        #expect(RoutineGroupCompletionStore.completedStepCount(for: routine, on: date) == 2)

        try RoutineGroupCompletionStore.undo(groupChange, in: context)
        #expect(RoutineGroupCompletionStore.isComplete(steps[0], on: date))
        #expect(!RoutineGroupCompletionStore.isComplete(steps[1], on: date))
    }

    @Test func stepCompletionsResetOnTheNextCivilDay() throws {
        let (container, routine, steps) = try makeGroupedRoutine()
        let context = container.mainContext
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Bogota")!
        let tonight = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 6, hour: 22)))
        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: tonight))
        _ = try RoutineGroupCompletionStore.complete(steps[0], in: routine, at: tonight, calendar: calendar, in: context)

        #expect(RoutineGroupCompletionStore.isComplete(steps[0], on: tonight, calendar: calendar))
        #expect(!RoutineGroupCompletionStore.isComplete(steps[0], on: tomorrow, calendar: calendar))
    }

    @Test func activeRoutineLimitAppliesToCreateAndReactivate() throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        for index in 0..<7 {
            try RoutineStore.create(title: "Routine \(index)", iconName: "moon", in: context)
        }
        #expect(throws: RoutineStoreError.activeRoutineLimit) {
            try RoutineStore.create(title: "Eighth", iconName: "moon", in: context)
        }
        let inactive = Routine(title: "Inactive", isActive: false)
        context.insert(inactive)
        #expect(throws: RoutineStoreError.activeRoutineLimit) {
            try RoutineStore.reactivate(inactive, in: context)
        }
    }

    @Test func orphanSweepDeletesStepAndCompletionOrphans() throws {
        let (container, _, steps) = try makeGroupedRoutine()
        let context = container.mainContext
        let completion = NightRoutineStepCompletion(date: .now, step: steps[0])
        context.insert(completion)
        steps[0].routine = nil
        completion.step = nil
        try context.save()

        try PersistenceMaintenance.removeOrphans(in: context)

        #expect(try context.fetch(FetchDescriptor<NightRoutineStep>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<NightRoutineStepCompletion>()).isEmpty)
    }

    private func makeGroupedRoutine() throws -> (ModelContainer, Routine, [NightRoutineStep]) {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        try RoutineStore.create(
            title: "Evening reset",
            iconName: "moon.stars",
            isGrouped: true,
            steps: [RoutineStepDraft(title: "Tea"), RoutineStepDraft(title: "Read")],
            in: context
        )
        let routine = try #require(try context.fetch(FetchDescriptor<Routine>()).first)
        return (container, routine, routine.steps.sorted { $0.order < $1.order })
    }
}
