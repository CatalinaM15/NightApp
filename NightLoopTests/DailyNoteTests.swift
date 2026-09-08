import Foundation
import SwiftData
import Testing
@testable import NightLoop

@MainActor
@Suite("Daily notes")
struct DailyNoteTests {
    @Test func notesAreStoredIndependentlyByCivilDateAndRemainEditable() throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        let calendar = testCalendar
        let today = date(2026, 9, 7, calendar: calendar)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

        try DailyNoteStore.setText("Today", on: today, calendar: calendar, in: context)
        try DailyNoteStore.setText("Tomorrow", on: tomorrow, calendar: calendar, in: context)
        try DailyNoteStore.setText("Today edited", on: today, calendar: calendar, in: context)

        #expect(try DailyNoteStore.text(on: today, calendar: calendar, in: context) == "Today edited")
        #expect(try DailyNoteStore.text(on: tomorrow, calendar: calendar, in: context) == "Tomorrow")
    }

    @Test func pruningRemovesPastNotesButKeepsTodayAndTomorrow() throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        let calendar = testCalendar
        let today = date(2026, 9, 7, calendar: calendar)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        try DailyNoteStore.setText("Old", on: yesterday, calendar: calendar, in: context)
        try DailyNoteStore.setText("Current", on: today, calendar: calendar, in: context)
        try DailyNoteStore.setText("Planned", on: tomorrow, calendar: calendar, in: context)

        try DailyNoteStore.pruneNotes(before: today, calendar: calendar, in: context)

        #expect(try DailyNoteStore.text(on: yesterday, calendar: calendar, in: context).isEmpty)
        #expect(try DailyNoteStore.text(on: today, calendar: calendar, in: context) == "Current")
        #expect(try DailyNoteStore.text(on: tomorrow, calendar: calendar, in: context) == "Planned")
    }

    private var testCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }
}
