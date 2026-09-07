import Foundation
import SwiftData

struct RoutineGroupCompletionChange {
    let stepCompletions: [NightRoutineStepCompletion]
    let parentCompletion: RoutineCompletion?
}

@MainActor
enum RoutineGroupCompletionStore {
    static func isComplete(
        _ step: NightRoutineStep,
        on date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Bool {
        let day = calendar.startOfDay(for: date)
        return step.completions.contains { calendar.isDate($0.date, inSameDayAs: day) }
    }

    static func completedStepCount(
        for routine: Routine,
        on date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Int {
        routine.steps.lazy.filter { isComplete($0, on: date, calendar: calendar) }.count
    }

    static func complete(
        _ step: NightRoutineStep,
        in routine: Routine,
        at date: Date = .now,
        calendar: Calendar = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent,
        in context: ModelContext
    ) throws -> RoutineGroupCompletionChange {
        guard step.routine?.id == routine.id, !isComplete(step, on: date, calendar: calendar) else {
            return RoutineGroupCompletionChange(stepCompletions: [], parentCompletion: nil)
        }

        let completesFinalStep = completedStepCount(for: routine, on: date, calendar: calendar) == routine.steps.count - 1
        let completion = NightRoutineStepCompletion(date: date, step: step, calendar: calendar)
        context.insert(completion)
        let parent = completesFinalStep
            ? try makeParentCompletionIfNeeded(for: routine, at: date, calendar: calendar, timeZone: timeZone, in: context)
            : nil
        try context.save()
        return RoutineGroupCompletionChange(stepCompletions: [completion], parentCompletion: parent)
    }

    static func completeGroup(
        _ routine: Routine,
        at date: Date = .now,
        calendar: Calendar = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent,
        in context: ModelContext
    ) throws -> RoutineGroupCompletionChange {
        var createdSteps: [NightRoutineStepCompletion] = []
        for step in routine.steps where !isComplete(step, on: date, calendar: calendar) {
            let completion = NightRoutineStepCompletion(date: date, step: step, calendar: calendar)
            context.insert(completion)
            createdSteps.append(completion)
        }
        let parent = try makeParentCompletionIfNeeded(
            for: routine,
            at: date,
            calendar: calendar,
            timeZone: timeZone,
            in: context
        )
        try context.save()
        return RoutineGroupCompletionChange(stepCompletions: createdSteps, parentCompletion: parent)
    }

    static func undo(_ change: RoutineGroupCompletionChange, in context: ModelContext) throws {
        change.stepCompletions.forEach(context.delete)
        if let parent = change.parentCompletion { context.delete(parent) }
        try context.save()
    }

    private static func makeParentCompletionIfNeeded(
        for routine: Routine,
        at date: Date,
        calendar: Calendar,
        timeZone: TimeZone,
        in context: ModelContext
    ) throws -> RoutineCompletion? {
        let dayKey = CivilDay(date: date, calendar: calendar).key
        guard try RoutineCompletionStore.completion(for: routine, dayKey: dayKey, in: context) == nil else { return nil }
        let completion = RoutineCompletion(
            dayKey: dayKey,
            completedAt: date,
            timeZoneIdentifier: timeZone.identifier,
            routine: routine
        )
        context.insert(completion)
        return completion
    }
}
