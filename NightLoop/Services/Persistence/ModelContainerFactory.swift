import SwiftData

@MainActor
enum ModelContainerFactory {
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: NightLoopSchemaV3.self)
        let configuration = ModelConfiguration(
            "NightLoopLocal",
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )

        let container = try ModelContainer(
            for: schema,
            migrationPlan: NightLoopMigrationPlan.self,
            configurations: configuration
        )
        try PersistenceMaintenance.removeOrphans(in: container.mainContext)
        return container
    }
}
