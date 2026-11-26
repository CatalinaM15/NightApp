import SwiftData

@MainActor
enum PersistenceMaintenance {
    static func removeOrphans(in context: ModelContext) throws {
        let orphanedSteps = try context.fetch(FetchDescriptor<NightRoutineStep>())
            .filter { $0.routine == nil }
        let orphanedCompletions = try context.fetch(FetchDescriptor<NightRoutineStepCompletion>())
            .filter { $0.step == nil }

        let stepIDs = Set(try context.fetch(FetchDescriptor<NightRoutineStep>()).filter { $0.routine != nil }.map(\.id))
        let orphanedGroups = try context.fetch(FetchDescriptor<DailyCareStepGroup>())
            .filter { !stepIDs.contains($0.stepID) }

        let orphanedSchedules = try context.fetch(FetchDescriptor<DailyStepSchedule>()).filter { !stepIDs.contains($0.stepID) }
        let orphanedLinks = try context.fetch(FetchDescriptor<DailyStepActivityLink>()).filter { !stepIDs.contains($0.stepID) }
        guard !orphanedLinks.isEmpty || !orphanedSchedules.isEmpty || !orphanedSteps.isEmpty || !orphanedCompletions.isEmpty || !orphanedGroups.isEmpty else { return }
        orphanedLinks.forEach(context.delete)
        orphanedSchedules.forEach(context.delete)
        orphanedGroups.forEach(context.delete)
        orphanedCompletions.forEach(context.delete)
        orphanedSteps.forEach(context.delete)
        try context.save()
    }
}
