import Foundation

struct CalendarColorComponents: Hashable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double
}

struct NightLoopCalendarEvent: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let calendarTitle: String
    let calendarColor: CalendarColorComponents

    func overlaps(_ range: Range<Date>) -> Bool {
        startDate < range.upperBound && endDate > range.lowerBound
    }
}

enum CalendarEventVisibility {
    static func shouldInclude(isCanceled: Bool, isDeclinedByCurrentUser: Bool) -> Bool {
        !isCanceled && !isDeclinedByCurrentUser
    }
}

enum CalendarEventOrdering {
    static func sort(_ events: [NightLoopCalendarEvent]) -> [NightLoopCalendarEvent] {
        events.sorted {
            if $0.isAllDay != $1.isAllDay { return $0.isAllDay }
            if $0.startDate != $1.startDate { return $0.startDate < $1.startDate }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }
}
