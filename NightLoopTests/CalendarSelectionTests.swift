import Foundation
import Testing
@testable import NightLoop

struct CalendarSelectionTests {
    @Test func allIncludesNewCalendarsButExplicitSelectionDoesNot() {
        let all = CalendarSelection()
        let selected = CalendarSelection(includesAll: false, identifiers: ["home"])
        #expect(all.resolvedIdentifiers(available: ["home", "new"]) == ["home", "new"])
        #expect(selected.resolvedIdentifiers(available: ["home", "new"]) == ["home"])
        #expect(selected.resolvedIdentifiers(available: ["new"]).isEmpty)
        #expect(!selected.contains("new"))
    }

    @Test func togglingFromAllPreservesOtherChoicesAndRoundTrips() {
        var selection = CalendarSelection()
        selection.toggle("work", available: ["home", "work"])
        #expect(!selection.includesAll)
        #expect(selection.identifiers == ["home"])
        #expect(CalendarSelection(storedValue: selection.storedValue) == selection)
        selection.toggle("home", available: ["home", "work"])
        #expect(selection.resolvedIdentifiers(available: ["home", "work"]).isEmpty)
        #expect(!selection.includesAll)
        #expect(CalendarSelection(storedValue: "").includesAll)
    }

    @Test func weekRangeHonorsFirstWeekdayAndDaylightSaving() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        calendar.firstWeekday = 1
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 11)))
        let range = try #require(calendar.weekRange(containing: date))
        #expect(calendar.component(.day, from: range.lowerBound) == 8)
        #expect(calendar.component(.day, from: range.upperBound) == 15)
        #expect(range.upperBound.timeIntervalSince(range.lowerBound) == 167 * 3600)
        calendar.firstWeekday = 2
        let mondayRange = try #require(calendar.weekRange(containing: date))
        #expect(calendar.component(.day, from: mondayRange.lowerBound) == 9)
        #expect(calendar.component(.day, from: mondayRange.upperBound) == 16)
    }
}
