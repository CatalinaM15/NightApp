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

        let required = try scheduledSteps(for: routine, on: date, calendar: calendar, in: context)
        guard required.contains(where: { $0.id == step.id }) else {
            return RoutineGroupCompletionChange(stepCompletions: [], parentCompletion: nil)
        }
        let completesFinalStep = required.filter { isComplete($0, on: date, calendar: calendar) }.count == required.count - 1
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
        let required = try scheduledSteps(for: routine, on: date, calendar: calendar, in: context)
        guard !required.isEmpty else { return RoutineGroupCompletionChange(stepCompletions: [], parentCompletion: nil) }
        var createdSteps: [NightRoutineStepCompletion] = []
        for step in required where !isComplete(step, on: date, calendar: calendar) {
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

    static func uncomplete(
        _ step: NightRoutineStep,
        in routine: Routine,
        at date: Date = .now,
        calendar: Calendar = .autoupdatingCurrent,
        in context: ModelContext
    ) throws {
        let day = calendar.startOfDay(for: date)
        step.completions
            .filter { calendar.isDate($0.date, inSameDayAs: day) }
            .forEach(context.delete)
        if let parent = try RoutineCompletionStore.completion(
            for: routine,
            dayKey: CivilDay(date: date, calendar: calendar).key,
            in: context
        ) {
            context.delete(parent)
        }
        try context.save()
    }

    static func uncompleteGroup(
        _ routine: Routine,
        at date: Date = .now,
        calendar: Calendar = .autoupdatingCurrent,
        in context: ModelContext
    ) throws {
        let day = calendar.startOfDay(for: date)
        for step in routine.steps {
            step.completions
                .filter { calendar.isDate($0.date, inSameDayAs: day) }
                .forEach(context.delete)
        }
        if let parent = try RoutineCompletionStore.completion(
            for: routine,
            dayKey: CivilDay(date: date, calendar: calendar).key,
            in: context
        ) {
            context.delete(parent)
        }
        try context.save()
    }

    static func synchronizeDailyCompletion(
        for routine: Routine, on date: Date, calendar: Calendar = .autoupdatingCurrent, in context: ModelContext
    ) throws {
        let required = try scheduledSteps(for: routine, on: date, calendar: calendar, in: context)
        if !required.isEmpty && required.allSatisfy({ isComplete($0, on: date, calendar: calendar) }) {
            _ = try makeParentCompletionIfNeeded(for: routine, at: date, calendar: calendar, timeZone: calendar.timeZone, in: context)
        } else if let parent = try RoutineCompletionStore.completion(for: routine, dayKey: CivilDay(date: date, calendar: calendar).key, in: context) {
            context.delete(parent)
        }
    }

    private static func scheduledSteps(
        for routine: Routine, on date: Date, calendar: Calendar, in context: ModelContext
    ) throws -> [NightRoutineStep] {
        guard routine.cardSlot == 4 else { return routine.steps }
        let schedules = try context.fetch(FetchDescriptor<DailyStepSchedule>())
        let links = try context.fetch(FetchDescriptor<DailyStepActivityLink>())
        return routine.steps.filter {
            DailyStepActivityLink.category(for: $0, in: links) == nil &&
            DailyStepSchedule.includes($0.id, on: date, in: schedules, calendar: calendar)
        }
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
