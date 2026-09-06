import SwiftData

enum ModelContainerFactory {
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: NightLoopSchemaV1.self)
        let configuration = ModelConfiguration(
            "NightLoopLocal",
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )

        return try ModelContainer(
            for: schema,
            migrationPlan: NightLoopMigrationPlan.self,
            configurations: configuration
        )
    }
}
