import Foundation
import SwiftData
import Testing
@testable import NightLoop

@MainActor
struct CompletionStoreTests {
    @Test func routineCompletionIsIdempotentForOneCivilDay() throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        let routine = Routine(title: "Plan tomorrow")
        context.insert(routine)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Bogota")!
        let first = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 6, hour: 20)))
        let second = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 6, hour: 23)))

        let firstCompletion = try RoutineCompletionStore.complete(routine, at: first, calendar: calendar, in: context)
        let secondCompletion = try RoutineCompletionStore.complete(routine, at: second, calendar: calendar, in: context)

        #expect(firstCompletion.id == secondCompletion.id)
        #expect(try context.fetch(FetchDescriptor<RoutineCompletion>()).count == 1)
    }

    @Test func finalStepCompletesProjectAndUndoReopensIt() throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        let project = NightProject(name: "Ship NightLoop")
        let step = ProjectStep(title: "Build foundation", order: 0, weekNumber: 1, project: project)
        context.insert(project)
        context.insert(step)

        try ProjectCompletionStore.complete(step, in: context)
        #expect(step.isCompleted)
        #expect(project.isCompleted)

        try ProjectCompletionStore.undo(step, in: context)
        #expect(!step.isCompleted)
        #expect(!project.isCompleted)
    }

    @Test func emptyProjectUsesProjectLevelCompletion() throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        let project = NightProject(name: "One-shot task")
        context.insert(project)

        try ProjectCompletionStore.completeEmptyProject(project, in: context)
        #expect(project.isCompleted)

        try ProjectCompletionStore.undoEmptyProject(project, in: context)
        #expect(!project.isCompleted)
    }
}
