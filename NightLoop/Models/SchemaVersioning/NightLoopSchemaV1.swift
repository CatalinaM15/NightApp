import Foundation
import SwiftData

enum NightLoopSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [Routine.self, RoutineCompletion.self, NightProject.self, ProjectStep.self] }

    @Model final class Routine {
        @Attribute(.unique) var id: UUID
        var title: String
        var iconName: String
        var sortOrder: Int
        var isActive: Bool
        var activePeriodStartedDayKey: String
        @Relationship(deleteRule: .cascade, inverse: \RoutineCompletion.routine) var completions: [RoutineCompletion]

        init(id: UUID, title: String, iconName: String, sortOrder: Int, isActive: Bool, activePeriodStartedDayKey: String) {
            self.id = id; self.title = title; self.iconName = iconName; self.sortOrder = sortOrder
            self.isActive = isActive; self.activePeriodStartedDayKey = activePeriodStartedDayKey; self.completions = []
        }
    }

    @Model final class RoutineCompletion {
        @Attribute(.unique) var id: UUID
        var dayKey: String
        var completedAt: Date
        var timeZoneIdentifier: String
        var routine: Routine?

        init(id: UUID, dayKey: String, completedAt: Date, timeZoneIdentifier: String, routine: Routine?) {
            self.id = id; self.dayKey = dayKey; self.completedAt = completedAt
            self.timeZoneIdentifier = timeZoneIdentifier; self.routine = routine
        }
    }

    @Model final class NightProject {
        @Attribute(.unique) var id: UUID
        var name: String
        var createdAt: Date
        var completedAt: Date?
        var colorTag: String?
        @Relationship(deleteRule: .cascade, inverse: \ProjectStep.project) var steps: [ProjectStep]

        init(id: UUID, name: String, createdAt: Date, completedAt: Date?, colorTag: String?) {
            self.id = id; self.name = name; self.createdAt = createdAt
            self.completedAt = completedAt; self.colorTag = colorTag; self.steps = []
        }
    }

    @Model final class ProjectStep {
        @Attribute(.unique) var id: UUID
        var title: String
        var order: Int
        var completedAt: Date?
        var weekNumber: Int
        var project: NightProject?

        init(id: UUID, title: String, order: Int, completedAt: Date?, weekNumber: Int, project: NightProject?) {
            self.id = id; self.title = title; self.order = order; self.completedAt = completedAt
            self.weekNumber = weekNumber; self.project = project
        }
    }
}

enum NightLoopSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] { [Routine.self, RoutineCompletion.self, NightProject.self, ProjectStep.self] }
}

enum NightLoopMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [NightLoopSchemaV1.self, NightLoopSchemaV2.self] }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: NightLoopSchemaV1.self, toVersion: NightLoopSchemaV2.self)]
    }
}
