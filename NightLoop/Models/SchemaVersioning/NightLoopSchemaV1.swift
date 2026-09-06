import SwiftData

enum NightLoopSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Routine.self, RoutineCompletion.self, NightProject.self, ProjectStep.self]
    }
}

enum NightLoopMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [NightLoopSchemaV1.self]
    }

    static var stages: [MigrationStage] { [] }
}
