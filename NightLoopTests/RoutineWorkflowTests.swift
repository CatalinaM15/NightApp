import Foundation
import SwiftData
import Testing
@testable import NightLoop

@MainActor
struct RoutineWorkflowTests {
    @Test func disabledRoutinePreservesHistoryAndHasNoCurrentStreak() throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        let routine = Routine(title: "Read", activePeriodStartedDayKey: "2026-09-01")
        context.insert(routine)
        routine.completions.append(RoutineCompletion(
            dayKey: "2026-09-05",
            completedAt: .now,
            timeZoneIdentifier: "America/Bogota",
            routine: routine
        ))

        try RoutineStore.disable(routine, in: context)

        #expect(!routine.isActive)
        #expect(routine.completions.count == 1)
        #expect(RoutineStreakCalculator.currentStreak(for: routine) == nil)
    }

    @Test func reactivationBeginsANewStreakPeriod() throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        let routine = Routine(title: "Read", isActive: false, activePeriodStartedDayKey: "2026-08-01")
        context.insert(routine)
        routine.completions.append(RoutineCompletion(
            dayKey: "2026-09-05",
            completedAt: .now,
            timeZoneIdentifier: "America/Bogota",
            routine: routine
        ))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Bogota")!
        let reactivationDate = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 6, hour: 10)))

        try RoutineStore.reactivate(routine, on: reactivationDate, calendar: calendar, in: context)

        #expect(routine.activePeriodStartedDayKey == "2026-09-06")
        #expect(RoutineStreakCalculator.currentStreak(for: routine, on: reactivationDate, calendar: calendar) == 0)
        #expect(routine.completions.count == 1)
    }

    @Test func duplicateRoutineTitlesAreRejectedCaseInsensitively() throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        try RoutineStore.create(title: "Read", iconName: "book.closed", in: context)

        #expect(throws: RoutineStoreError.duplicateTitle) {
            try RoutineStore.create(title: "  read  ", iconName: "book.closed", in: context)
        }
    }

    @Test func movingRoutineReordersActiveRoutines() throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        let first = Routine(title: "First", sortOrder: 0)
        let second = Routine(title: "Second", sortOrder: 1)
        context.insert(first)
        context.insert(second)

        try RoutineStore.move(second, by: -1, in: context)

        #expect(second.sortOrder == 0)
        #expect(first.sortOrder == 1)
    }

    @Test func dayCoordinatorRollsOverOnlyWhenCivilDayChanges() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Bogota")!
        let evening = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 6, hour: 22)))
        let sameDay = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 6, hour: 23)))
        let nextMorning = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: 8)))
        let coordinator = JournalDayCoordinator(now: evening, calendar: calendar, observesSystem: false)

        #expect(!coordinator.shouldRollOver(to: sameDay))
        #expect(coordinator.shouldRollOver(to: nextMorning))
        coordinator.refresh(at: nextMorning)
        #expect(calendar.isDate(coordinator.visibleDate, inSameDayAs: nextMorning))
    }

    @Test func undoCoordinatorKeepsOnlyTheLastAction() {
        let coordinator = CompletionUndoCoordinator()
        var result = ""
        coordinator.offer(message: "First") { result = "first" }
        coordinator.offer(message: "Second") { result = "second" }

        coordinator.undo()

        #expect(result == "second")
        #expect(coordinator.message == nil)
    }

    @Test func undoCoordinatorExpires() async throws {
        let coordinator = CompletionUndoCoordinator(expiry: .milliseconds(20))
        coordinator.offer(message: "Completed") {}
        try await Task.sleep(for: .milliseconds(50))
        #expect(coordinator.message == nil)
    }
}
