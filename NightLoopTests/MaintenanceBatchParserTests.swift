import Foundation
import SwiftData
import Testing
@testable import NightLoop

@MainActor
struct MaintenanceBatchParserTests {
    @Test func onePlanCanAssignEveryWeekdayAndLongerFrequencies() throws {
        let text = """
        Monday:
        Laundry
        - Bedding
        Tuesday: Bathroom
        Wednesday:
        Vacuum
        Thursday:
        Kitchen
        Friday:
        Light reset
        Saturday:
        Supplies
        Sunday:
        Meal prep
        Monthly:
        Clean oven
        Every 3 Months:
        Clean windows
        Every 6 Months:
        Curtains
        Yearly:
        Home review
        """
        let entries = try MaintenanceBatchParser.parse(text, kind: .chores, defaultFrequency: .yearly, defaultWeekday: 6)
        #expect(entries.count == 12)
        #expect(entries.prefix(8).map(\.weekday) == [0, 0, 1, 2, 3, 4, 5, 6])
        #expect(entries.prefix(8).allSatisfy { $0.frequency == .weekly })
        #expect(entries.suffix(4).map(\.frequency) == [.monthly, .quarterly, .semiannual, .yearly])
        #expect(entries.suffix(4).allSatisfy { $0.weekday == nil })
        #expect(entries[1].title == "Bedding")
        #expect(entries[2].title == "Bathroom")
    }

    @Test func plainInputKeepsDefaultsAndHeadingsAndBulletsHandleWindowsLines() throws {
        let entries = try MaintenanceBatchParser.parse(" Old task \r\nMON:\r\n• Laundry\r\nMonthly: Clean oven\r\n* Monthly", kind: .chores,
                                                       defaultFrequency: .semiannual, defaultWeekday: 4)
        #expect(entries.map(\.title) == ["Old task", "Laundry", "Clean oven", "Monthly"])
        #expect(entries.map(\.frequency) == [.semiannual, .weekly, .monthly, .monthly])
        #expect(entries.map(\.weekday) == [nil, 0, nil, nil])
        #expect(try MaintenanceBatchParser.parse(" \r\nMonthly:\r\n", kind: .chores, defaultFrequency: .monthly, defaultWeekday: 0).isEmpty)
    }

    @Test func invalidHeadersAndDoctorWeekdaysReportErrorsInsteadOfCreatingMistitledEntries() throws {
        #expect(throws: MaintenanceBatchError.self) {
            try MaintenanceBatchParser.parse("Monthly:\nClean oven\nEvery 2 months:\nOther", kind: .chores, defaultFrequency: .monthly, defaultWeekday: 0)
        }
        #expect(throws: MaintenanceBatchError.self) {
            try MaintenanceBatchParser.parse("Monday:\nDentist", kind: .doctorVisits, defaultFrequency: .monthly, defaultWeekday: 0)
        }
        #expect(throws: MaintenanceBatchError.self) {
            try MaintenanceBatchParser.parse("Weekly:\nLaundry", kind: .chores, defaultFrequency: .monthly, defaultWeekday: nil)
        }
        do {
            _ = try MaintenanceBatchParser.parse("Monthly:\r\nOven\r\nUnknown:\r\nOther", kind: .chores, defaultFrequency: .monthly, defaultWeekday: 0)
            Issue.record("Expected an invalid heading")
        } catch {
            #expect(error.localizedDescription.hasPrefix("Line 3:"))
        }
    }

    @Test func doctorsCanUseDifferentFixedFrequenciesAndTemplatesContainNoExampleEntries() throws {
        let entries = try MaintenanceBatchParser.parse("Monthly:\nDermatologist\nEvery 6 Months:\nDentist\nAnnual:\nVision", kind: .doctorVisits,
                                                       defaultFrequency: .quarterly, defaultWeekday: nil)
        #expect(entries.map(\.frequency) == [.monthly, .semiannual, .yearly])
        for kind in MaintenanceKind.allCases {
            #expect(try MaintenanceBatchParser.parse(MaintenanceBatchParser.template(for: kind), kind: kind,
                                                     defaultFrequency: .monthly, defaultWeekday: 0).isEmpty)
        }
    }

    @Test func doctorBatchSavesAllFourFrequenciesTogether() throws {
        let text = """
        Monthly:
        Monthly review
        Every 3 Months:
        Quarterly review
        Every 6 Months:
        Dentist
        Yearly:
        Vision
        """
        let entries = try MaintenanceBatchParser.parse(text, kind: .doctorVisits, defaultFrequency: .monthly, defaultWeekday: nil)
        #expect(entries.map(\.frequency) == [.monthly, .quarterly, .semiannual, .yearly])
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        try MaintenanceStore.createBatch(entries: entries, kind: .doctorVisits, in: context)
        let fresh = ModelContext(container)
        let items = try fresh.fetch(FetchDescriptor<MaintenanceItem>())
        #expect(items.count == 4)
        #expect(Set(items.map(\.frequency)) == ["monthly", "quarterly", "semiannual", "yearly"])
        #expect(items.allSatisfy { $0.kind == "doctorVisits" && $0.weekday == nil })
    }

    @Test func mixedBatchSavesEachScheduleAndInvalidEntriesSaveNothing() throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        let entries = try MaintenanceBatchParser.parse("Monday: Laundry\nTuesday: Bathroom\nMonthly: Oven\nYearly: Repairs", kind: .chores,
                                                       defaultFrequency: .monthly, defaultWeekday: 0)
        let items = try MaintenanceStore.createBatch(entries: entries, kind: .chores, in: context)
        #expect(items.map(\.frequency) == ["weekly", "weekly", "monthly", "yearly"])
        #expect(items.map(\.weekday) == [0, 1, nil, nil])
        #expect(items.map(\.title) == ["Laundry", "Bathroom", "Oven", "Repairs"])
        #expect(throws: MaintenanceStoreError.invalidSchedule) {
            try MaintenanceStore.createBatch(entries: [
                MaintenanceBatchEntry(title: "Valid", frequency: .monthly),
                MaintenanceBatchEntry(title: "Invalid", frequency: .weekly, weekday: nil)
            ], kind: .chores, in: context)
        }
        #expect(throws: MaintenanceStoreError.invalidSchedule) {
            try MaintenanceStore.createBatch(entries: [MaintenanceBatchEntry(title: "Dentist", frequency: .weekly, weekday: 0)], kind: .doctorVisits, in: context)
        }
        let fresh = ModelContext(container)
        #expect(try fresh.fetch(FetchDescriptor<MaintenanceItem>()).count == 4)
    }
}
