import Foundation
import SwiftData

@MainActor
enum ProjectCompletionStore {
    static func complete(
        _ step: ProjectStep,
        at date: Date = .now,
        in context: ModelContext
    ) throws {
        guard step.completedAt == nil else { return }
        step.completedAt = date

        if let project = step.project,
           !project.steps.isEmpty,
           project.steps.allSatisfy(\.isCompleted) {
            project.completedAt = date
        }
        try context.save()
    }

    static func undo(
        _ step: ProjectStep,
        in context: ModelContext
    ) throws {
        guard step.completedAt != nil else { return }
        step.completedAt = nil
        step.project?.completedAt = nil
        try context.save()
    }

    static func completeEmptyProject(
        _ project: NightProject,
        at date: Date = .now,
        in context: ModelContext
    ) throws {
        guard project.steps.isEmpty, project.completedAt == nil else { return }
        project.completedAt = date
        try context.save()
    }

    static func undoEmptyProject(_ project: NightProject, in context: ModelContext) throws {
        guard project.steps.isEmpty else { return }
        project.completedAt = nil
        try context.save()
    }
}
