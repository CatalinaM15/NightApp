import Foundation
import Testing
@testable import NightLoop

struct CalendarEventTests {
    @Test func canceledAndDeclinedEventsAreExcluded() {
        #expect(!CalendarEventVisibility.shouldInclude(isCanceled: true, isDeclinedByCurrentUser: false))
        #expect(!CalendarEventVisibility.shouldInclude(isCanceled: false, isDeclinedByCurrentUser: true))
        #expect(!CalendarEventVisibility.shouldInclude(isCanceled: true, isDeclinedByCurrentUser: true))
        #expect(CalendarEventVisibility.shouldInclude(isCanceled: false, isDeclinedByCurrentUser: false))
    }

    @Test func eventOverlapIncludesAllDayAndMultiDayIntersections() throws {
        let range = Date(timeIntervalSinceReferenceDate: 1_000)..<Date(timeIntervalSinceReferenceDate: 2_000)
        let color = CalendarColorComponents(red: 1, green: 0, blue: 0, alpha: 1)
        let overlapping = NightLoopCalendarEvent(
            id: "overlap",
            title: "Multi-day",
            startDate: Date(timeIntervalSinceReferenceDate: 500),
            endDate: Date(timeIntervalSinceReferenceDate: 1_500),
            isAllDay: true,
            calendarTitle: "Home",
            calendarColor: color
        )
        let endingAtBoundary = NightLoopCalendarEvent(
            id: "boundary",
            title: "Yesterday",
            startDate: Date(timeIntervalSinceReferenceDate: 500),
            endDate: range.lowerBound,
            isAllDay: false,
            calendarTitle: "Home",
            calendarColor: color
        )

        #expect(overlapping.overlaps(range))
        #expect(!endingAtBoundary.overlaps(range))
    }

    @Test func allDayEventsSortBeforeTimedEventsThenByStart() {
        let color = CalendarColorComponents(red: 0, green: 0, blue: 1, alpha: 1)
        func event(_ id: String, allDay: Bool, start: TimeInterval) -> NightLoopCalendarEvent {
            NightLoopCalendarEvent(
                id: id,
                title: id,
                startDate: Date(timeIntervalSinceReferenceDate: start),
                endDate: Date(timeIntervalSinceReferenceDate: start + 100),
                isAllDay: allDay,
                calendarTitle: "Test",
                calendarColor: color
            )
        }

        let sorted = CalendarEventOrdering.sort([
            event("late", allDay: false, start: 1_500),
            event("early", allDay: false, start: 1_100),
            event("all-day", allDay: true, start: 1_000)
        ])

        #expect(sorted.map(\.id) == ["all-day", "early", "late"])
    }
}
