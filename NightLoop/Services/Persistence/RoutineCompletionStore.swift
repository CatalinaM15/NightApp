import Foundation
import SwiftData

@MainActor
enum RoutineCompletionStore {
    static func completion(
        for routine: Routine,
        dayKey: String,
        in context: ModelContext
    ) throws -> RoutineCompletion? {
        let descriptor = FetchDescriptor<RoutineCompletion>(
            predicate: #Predicate { $0.dayKey == dayKey }
        )
        return try context.fetch(descriptor).first(where: { $0.routine?.id == routine.id })
    }

    @discardableResult
    static func complete(
        _ routine: Routine,
        at date: Date = .now,
        calendar: Calendar = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent,
        in context: ModelContext
    ) throws -> RoutineCompletion {
        let dayKey = CivilDay(date: date, calendar: calendar).key
        if let existing = try completion(for: routine, dayKey: dayKey, in: context) {
            return existing
        }

        let completion = RoutineCompletion(
            dayKey: dayKey,
            completedAt: date,
            timeZoneIdentifier: timeZone.identifier,
            routine: routine
        )
        context.insert(completion)
        try context.save()
        return completion
    }

    static func undo(_ completion: RoutineCompletion, in context: ModelContext) throws {
        context.delete(completion)
        try context.save()
    }
}
