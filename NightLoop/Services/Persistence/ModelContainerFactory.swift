import SwiftData

@MainActor
enum ModelContainerFactory {
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: NightLoopSchemaV4.self)
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
        if !inMemory {
            try TodayCardsStore.bootstrap(in: container.mainContext)
        }
        return container
    }
}
