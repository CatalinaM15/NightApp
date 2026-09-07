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

    @Model final class Routine {
        @Attribute(.unique) var id: UUID
        var title: String
        var iconName: String
        var sortOrder: Int
        var isActive: Bool
        var activePeriodStartedDayKey: String
        var scheduledWeekdaysMask: Int = RoutineSchedule.allDaysMask
        @Relationship(deleteRule: .cascade, inverse: \RoutineCompletion.routine) var completions: [RoutineCompletion]

        init(id: UUID, title: String, iconName: String, sortOrder: Int, isActive: Bool, activePeriodStartedDayKey: String, scheduledWeekdaysMask: Int) {
            self.id = id; self.title = title; self.iconName = iconName; self.sortOrder = sortOrder
            self.isActive = isActive; self.activePeriodStartedDayKey = activePeriodStartedDayKey
            self.scheduledWeekdaysMask = scheduledWeekdaysMask; self.completions = []
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

enum NightLoopSchemaV3: VersionedSchema {
    static var versionIdentifier = Schema.Version(3, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Routine.self, RoutineCompletion.self, NightProject.self, ProjectStep.self,
         NightRoutineStep.self, NightRoutineStepCompletion.self]
    }

    @Model final class Routine {
        @Attribute(.unique) var id: UUID
        var title: String
        var iconName: String
        var sortOrder: Int
        var isActive: Bool
        var activePeriodStartedDayKey: String
        var scheduledWeekdaysMask: Int = RoutineSchedule.allDaysMask
        var isGrouped: Bool = false
        @Relationship(deleteRule: .cascade, inverse: \RoutineCompletion.routine) var completions: [RoutineCompletion]
        @Relationship(deleteRule: .cascade, inverse: \NightRoutineStep.routine) var steps: [NightRoutineStep]

        init(id: UUID, title: String, iconName: String, sortOrder: Int, isActive: Bool,
             activePeriodStartedDayKey: String, scheduledWeekdaysMask: Int, isGrouped: Bool) {
            self.id = id; self.title = title; self.iconName = iconName; self.sortOrder = sortOrder
            self.isActive = isActive; self.activePeriodStartedDayKey = activePeriodStartedDayKey
            self.scheduledWeekdaysMask = scheduledWeekdaysMask; self.isGrouped = isGrouped
            self.completions = []; self.steps = []
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

    @Model final class NightRoutineStep {
        @Attribute(.unique) var id: UUID
        var title: String
        var order: Int
        var routine: Routine?
        @Relationship(deleteRule: .cascade, inverse: \NightRoutineStepCompletion.step) var completions: [NightRoutineStepCompletion]
        init(id: UUID, title: String, order: Int, routine: Routine?) {
            self.id = id; self.title = title; self.order = order; self.routine = routine; self.completions = []
        }
    }

    @Model final class NightRoutineStepCompletion {
        @Attribute(.unique) var id: UUID
        var date: Date
        var step: NightRoutineStep?
        init(id: UUID, date: Date, step: NightRoutineStep?) {
            self.id = id; self.date = date; self.step = step
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

enum NightLoopSchemaV4: VersionedSchema {
    static var versionIdentifier = Schema.Version(4, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Routine.self, RoutineCompletion.self, NightProject.self, ProjectStep.self,
         NightRoutineStep.self, NightRoutineStepCompletion.self, CardOption.self,
         SlotSelectionHistory.self, ExperimentArchiveRecord.self]
    }
}

enum NightLoopMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [NightLoopSchemaV1.self, NightLoopSchemaV2.self, NightLoopSchemaV3.self, NightLoopSchemaV4.self]
    }
    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: NightLoopSchemaV1.self, toVersion: NightLoopSchemaV2.self),
            .lightweight(fromVersion: NightLoopSchemaV2.self, toVersion: NightLoopSchemaV3.self),
            .lightweight(fromVersion: NightLoopSchemaV3.self, toVersion: NightLoopSchemaV4.self)
        ]
    }
}
