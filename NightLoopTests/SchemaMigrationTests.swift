import Foundation
import SwiftData
import Testing
@testable import NightLoop

@MainActor
@Suite("Schema migrations")
struct SchemaMigrationTests {
    @Test func versionOneRoutinesMigrateToAllDays() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "NightLoopMigration-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "NightLoop.store")

        do {
            let oldSchema = Schema(versionedSchema: NightLoopSchemaV1.self)
            let oldConfiguration = ModelConfiguration("Migration", schema: oldSchema, url: storeURL, cloudKitDatabase: .none)
            let oldContainer = try ModelContainer(for: oldSchema, configurations: oldConfiguration)
            oldContainer.mainContext.insert(NightLoopSchemaV1.Routine(
                id: UUID(),
                title: "Existing ritual",
                iconName: "moon.stars",
                sortOrder: 0,
                isActive: true,
                activePeriodStartedDayKey: "2026-09-01"
            ))
            try oldContainer.mainContext.save()
        }

        let newSchema = Schema(versionedSchema: NightLoopSchemaV4.self)
        let newConfiguration = ModelConfiguration("Migration", schema: newSchema, url: storeURL, cloudKitDatabase: .none)
        let migratedContainer = try ModelContainer(
            for: newSchema,
            migrationPlan: NightLoopMigrationPlan.self,
            configurations: newConfiguration
        )
        let routines = try migratedContainer.mainContext.fetch(FetchDescriptor<Routine>())

        #expect(routines.count == 1)
        #expect(routines.first?.scheduledWeekdaysMask == RoutineSchedule.allDaysMask)
        #expect(routines.first?.isGrouped == false)
        #expect(routines.first?.steps.isEmpty == true)
        #expect(routines.first?.cardSlot == nil)
    }
}
