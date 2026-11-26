import Foundation
import SwiftData
import Testing
@testable import NightLoop

@MainActor
@Suite("Chores and doctor visits")
struct MaintenanceWorkflowTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Bogota")!
        calendar.firstWeekday = 2
        return calendar
    }

    private func day(_ day: Int) -> Date { date(2026, 11, day) }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: NightLoopSchemaV9.self)
        return try ModelContainer(for: schema, migrationPlan: NightLoopMigrationPlan.self,
                                  configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    }

    @Test func fixedSchedulesAndValidationRejectBadInputBeforeInserting() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let now = day(25)
        #expect(throws: MaintenanceStoreError.emptyTitle) {
            try MaintenanceStore.create(title: " \n ", kind: .chores, frequency: .monthly, in: context)
        }
        #expect(throws: MaintenanceStoreError.invalidSchedule) {
            try MaintenanceStore.create(title: "Dentist", kind: .doctorVisits, frequency: .weekly, weekday: 0, in: context)
        }
        #expect(throws: MaintenanceStoreError.invalidSchedule) {
            try MaintenanceStore.create(title: "Laundry", kind: .chores, frequency: .weekly, weekday: 7, in: context)
        }
        #expect(throws: MaintenanceStoreError.invalidSchedule) {
            try MaintenanceStore.create(title: "Laundry", kind: .chores, frequency: .weekly, in: context)
        }
        #expect(throws: MaintenanceStoreError.futureDate) {
            try MaintenanceStore.create(title: "Laundry", kind: .chores, frequency: .monthly, lastDate: day(26), now: now, calendar: calendar, in: context)
        }
        #expect(try context.fetch(FetchDescriptor<MaintenanceItem>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<MaintenanceRecord>()).isEmpty)
        #expect(MaintenanceKind.chores.frequencies.count == 5)
        #expect(MaintenanceKind.doctorVisits.frequencies == [.monthly, .quarterly, .semiannual, .yearly])
        let item = try MaintenanceStore.create(title: " Laundry ", kind: .chores, frequency: .weekly, weekday: 0, in: context)
        #expect(item.title == "Laundry")
        #expect(item.weekday == RoutineWeekday.monday.rawValue)
    }

    @Test func editingPreservesIdentityAndHistoryAndClearsWeeklyDayWhenFrequencyChanges() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let item = try MaintenanceStore.create(title: "Kitchen", kind: .chores, frequency: .weekly, weekday: 3,
                                               lastDate: day(20), now: day(25), calendar: calendar, in: context)
        let itemID = item.id
        let recordID = try #require(item.records.first?.id)
        try MaintenanceStore.update(item, title: " Deep clean kitchen ", frequency: .quarterly, weekday: 3, in: context)
        #expect(item.title == "Deep clean kitchen")
        #expect(item.frequency == MaintenanceFrequency.quarterly.rawValue)
        #expect(item.weekday == nil)
        #expect(item.id == itemID)
        #expect(item.records.first?.id == recordID)
        #expect(throws: MaintenanceStoreError.emptyTitle) {
            try MaintenanceStore.update(item, title: "  ", frequency: .yearly, in: context)
        }
        #expect(item.title == "Deep clean kitchen")
        #expect(item.frequency == MaintenanceFrequency.quarterly.rawValue)
    }

    @Test func backdatingDoesNotReplaceTheLatestRecordAndDuplicateDaysAreRejected() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let now = day(25)
        let item = try MaintenanceStore.create(title: "Dentist", kind: .doctorVisits, frequency: .semiannual, in: context)
        #expect(item.elapsedText(on: now, calendar: calendar) == "No date recorded")
        let recent = try MaintenanceStore.record(item, on: date(2026, 10, 25), now: now, calendar: calendar, in: context)
        try MaintenanceStore.record(item, on: date(2026, 4, 25), now: now, calendar: calendar, in: context)
        #expect(item.records.count == 2)
        #expect(item.lastRecordedDate == recent.date)
        #expect(item.elapsedText(on: now, calendar: calendar) == "1 month ago")
        #expect(throws: MaintenanceStoreError.duplicateDate) {
            try MaintenanceStore.record(item, on: date(2026, 10, 25).addingTimeInterval(3600), now: now, calendar: calendar, in: context)
        }
        #expect(throws: MaintenanceStoreError.futureDate) {
            try MaintenanceStore.record(item, on: day(26), now: now, calendar: calendar, in: context)
        }
        #expect(item.records.count == 2)
    }

    @Test func historyDatesCanBeCorrectedWithoutDuplicatingOrLosingOtherDates() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let now = day(25)
        let item = try MaintenanceStore.create(title: "Clean oven", kind: .chores, frequency: .monthly, in: context)
        let first = try MaintenanceStore.record(item, on: day(20), now: now, calendar: calendar, in: context)
        let second = try MaintenanceStore.record(item, on: day(24), now: now, calendar: calendar, in: context)
        let secondID = second.id
        try MaintenanceStore.updateDate(second, to: day(22), now: now, calendar: calendar, in: context)
        #expect(second.id == secondID)
        #expect(item.elapsedText(on: now, calendar: calendar) == "3 days ago")
        #expect(throws: MaintenanceStoreError.duplicateDate) {
            try MaintenanceStore.updateDate(second, to: first.date, now: now, calendar: calendar, in: context)
        }
        #expect(calendar.isDate(second.date, inSameDayAs: day(22)))
        #expect(throws: MaintenanceStoreError.futureDate) {
            try MaintenanceStore.updateDate(second, to: day(26), now: now, calendar: calendar, in: context)
        }
        #expect(item.records.count == 2)
    }

    @Test func undoRemovesOnlyItsRecordAndDeletingAnEntryCascadesItsHistory() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let now = day(25)
        let item = try MaintenanceStore.create(title: "Dermatologist", kind: .doctorVisits, frequency: .yearly, in: context)
        try MaintenanceStore.record(item, on: day(20), now: now, calendar: calendar, in: context)
        let latest = try MaintenanceStore.record(item, on: now, now: now, calendar: calendar, in: context)
        try MaintenanceStore.removeRecord(id: latest.id, in: context)
        #expect(item.records.count == 1)
        #expect(calendar.isDate(try #require(item.lastRecordedDate), inSameDayAs: day(20)))
        try MaintenanceStore.removeRecord(id: UUID(), in: context)
        #expect(item.records.count == 1)
        try MaintenanceStore.delete(item, in: context)
        #expect(try context.fetch(FetchDescriptor<MaintenanceItem>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<MaintenanceRecord>()).isEmpty)
    }

    @Test func weeklyChecksResetAtTheCalendarWeekBoundaryAndLongerPeriodsUseElapsedTime() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let item = try MaintenanceStore.create(title: "Bedding", kind: .chores, frequency: .weekly, weekday: 6, in: context)
        try MaintenanceStore.record(item, on: day(22), now: day(25), calendar: calendar, in: context)
        #expect(item.isRecordedThisWeek(on: day(22), calendar: calendar))
        #expect(!item.isRecordedThisWeek(on: day(23), calendar: calendar))
        #expect(!item.isRecorded(on: day(25), calendar: calendar))
        try MaintenanceStore.record(item, on: day(25), now: day(25), calendar: calendar, in: context)
        #expect(item.isRecordedThisWeek(on: day(25), calendar: calendar))
        #expect(item.elapsedText(on: day(25), calendar: calendar) == "Today")
    }

    @Test func batchInputHandlesBlankLinesAndWindowsLineEndings() {
        #expect(MaintenanceStore.batchTitles(from: " Laundry \r\n\r\nClean oven\n  Bedding  \r") == ["Laundry", "Clean oven", "Bedding"])
        #expect(MaintenanceStore.batchTitles(from: " \n\t\r\n ").isEmpty)
    }

    @Test func batchCreatesIndependentEntriesWithSharedScheduleAndOptionalHistory() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let chores = try MaintenanceStore.createBatch(titles: [" Laundry ", "Bedding"], kind: .chores,
                                                      frequency: .weekly, weekday: 0, in: context)
        #expect(chores.map(\.title) == ["Laundry", "Bedding"])
        #expect(Set(chores.map(\.id)).count == 2)
        #expect(chores.allSatisfy { $0.weekday == 0 && $0.frequency == "weekly" && $0.records.isEmpty })
        let doctors = try MaintenanceStore.createBatch(titles: ["Dentist", "Dermatologist"], kind: .doctorVisits,
                                                       frequency: .semiannual, lastDate: day(20), now: day(25), calendar: calendar, in: context)
        #expect(doctors.allSatisfy { $0.kind == "doctorVisits" && $0.frequency == "semiannual" && $0.weekday == nil && $0.records.count == 1 })
        #expect(Set(doctors.flatMap(\.records).map(\.id)).count == 2)
        try MaintenanceStore.update(chores[0], title: "Laundry and towels", frequency: .monthly, in: context)
        #expect(chores[1].title == "Bedding")
        #expect(chores[1].frequency == "weekly")
        let freshContext = ModelContext(container)
        #expect(try freshContext.fetch(FetchDescriptor<MaintenanceItem>()).count == 4)
        #expect(try freshContext.fetch(FetchDescriptor<MaintenanceRecord>()).count == 2)
    }

    @Test func invalidBatchesSaveNothingAndPreserveExistingEntries() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let existing = try MaintenanceStore.create(title: "Keep this", kind: .chores, frequency: .yearly, in: context)
        #expect(throws: MaintenanceStoreError.emptyTitle) {
            try MaintenanceStore.createBatch(titles: [], kind: .chores, frequency: .monthly, in: context)
        }
        #expect(throws: MaintenanceStoreError.emptyTitle) {
            try MaintenanceStore.createBatch(titles: ["Valid", " ", "Another"], kind: .chores, frequency: .monthly, in: context)
        }
        #expect(throws: MaintenanceStoreError.invalidSchedule) {
            try MaintenanceStore.createBatch(titles: ["Dentist", "Vision"], kind: .doctorVisits, frequency: .weekly, weekday: 0, in: context)
        }
        #expect(throws: MaintenanceStoreError.futureDate) {
            try MaintenanceStore.createBatch(titles: ["Oven", "Bathroom"], kind: .chores, frequency: .monthly,
                                             lastDate: day(26), now: day(25), calendar: calendar, in: context)
        }
        #expect(try context.fetch(FetchDescriptor<MaintenanceItem>()).map(\.id) == [existing.id])
        #expect(try context.fetch(FetchDescriptor<MaintenanceRecord>()).isEmpty)
    }

    @Test func versionSixMigratesWithoutChangingExistingDataAndNewHistoryPersists() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Migration.store")
        let stepID = UUID()
        let projectID = UUID()
        let recordDate = day(20)
        do {
            let schema = Schema(versionedSchema: NightLoopSchemaV6.self)
            let configuration = ModelConfiguration("Migration", schema: schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: configuration)
            let context = container.mainContext
            let routine = Routine(title: "Daily Care", isGrouped: true, cardSlot: 4)
            context.insert(routine)
            let step = NightRoutineStep(id: stepID, title: "Skincare", order: 0, routine: routine)
            context.insert(step)
            context.insert(DailyCareStepGroup(stepID: stepID, period: .morning))
            context.insert(NightRoutineStepCompletion(date: recordDate, step: step, calendar: calendar))
            context.insert(NightProject(id: projectID, name: "Keep project"))
            context.insert(DailyNote(date: recordDate, text: "Keep note", calendar: calendar))
            context.insert(CardOption(category: .bodyCare, name: "Hair Wash", scheduledWeekdaysMask: RoutineWeekday.tuesday.bit, sortOrder: 0))
            try context.save()
        }
        var itemID: UUID!
        do {
            let schema = Schema(versionedSchema: NightLoopSchemaV9.self)
            let configuration = ModelConfiguration("Migration", schema: schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, migrationPlan: NightLoopMigrationPlan.self, configurations: configuration)
            let context = container.mainContext
            #expect(try context.fetch(FetchDescriptor<NightRoutineStep>()).first?.id == stepID)
            #expect(try context.fetch(FetchDescriptor<NightRoutineStepCompletion>()).count == 1)
            #expect(try context.fetch(FetchDescriptor<DailyCareStepGroup>()).first?.period == "morning")
            #expect(try context.fetch(FetchDescriptor<NightProject>()).first?.id == projectID)
            #expect(try context.fetch(FetchDescriptor<DailyNote>()).first?.text == "Keep note")
            #expect(try context.fetch(FetchDescriptor<CardOption>()).first?.scheduledWeekdaysMask == RoutineWeekday.tuesday.bit)
            #expect(try context.fetch(FetchDescriptor<MaintenanceItem>()).isEmpty)
            let item = try MaintenanceStore.create(title: "Dentist", kind: .doctorVisits, frequency: .semiannual,
                                                   lastDate: recordDate, now: day(25), calendar: calendar, in: context)
            itemID = item.id
        }
        let schema = Schema(versionedSchema: NightLoopSchemaV9.self)
        let configuration = ModelConfiguration("Migration", schema: schema, url: url, cloudKitDatabase: .none)
        let reopened = try ModelContainer(for: schema, migrationPlan: NightLoopMigrationPlan.self, configurations: configuration)
        let item = try #require(try reopened.mainContext.fetch(FetchDescriptor<MaintenanceItem>()).first)
        #expect(item.id == itemID)
        #expect(item.kind == MaintenanceKind.doctorVisits.rawValue)
        #expect(item.frequency == MaintenanceFrequency.semiannual.rawValue)
        #expect(item.records.count == 1)
        #expect(calendar.isDate(try #require(item.lastRecordedDate), inSameDayAs: recordDate))
    }
}
