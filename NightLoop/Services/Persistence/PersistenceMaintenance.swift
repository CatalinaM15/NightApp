import SwiftData

@MainActor
enum PersistenceMaintenance {
    static func removeOrphans(in context: ModelContext) throws {
        let orphanedSteps = try context.fetch(FetchDescriptor<NightRoutineStep>())
            .filter { $0.routine == nil }
        let orphanedCompletions = try context.fetch(FetchDescriptor<NightRoutineStepCompletion>())
            .filter { $0.step == nil }

        guard !orphanedSteps.isEmpty || !orphanedCompletions.isEmpty else { return }
        orphanedCompletions.forEach(context.delete)
        orphanedSteps.forEach(context.delete)
        try context.save()
    }
}
