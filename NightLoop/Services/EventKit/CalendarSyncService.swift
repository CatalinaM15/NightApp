import AppKit
import EventKit
import Foundation

enum CalendarSyncError: LocalizedError {
    case accessUnavailable
    case invalidDayRange

    var errorDescription: String? {
        switch self {
        case .accessUnavailable: "Calendar access is unavailable."
        case .invalidDayRange: "NightLoop could not calculate the selected date range."
        }
    }
}

@MainActor
final class CalendarSyncService {
    private let eventStore: EKEventStore

    init(eventStore: EKEventStore) {
        self.eventStore = eventStore
    }

    func fetchEvents(
        on date: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> [NightLoopCalendarEvent] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            throw CalendarSyncError.accessUnavailable
        }
        guard let range = calendar.dayRange(containing: date) else {
            throw CalendarSyncError.invalidDayRange
        }

        let predicate = eventStore.predicateForEvents(
            withStart: range.lowerBound,
            end: range.upperBound,
            calendars: nil
        )

        let events = eventStore.events(matching: predicate).compactMap { event -> NightLoopCalendarEvent? in
            let isDeclined = event.attendees?.contains {
                $0.isCurrentUser && $0.participantStatus == .declined
            } ?? false
            guard CalendarEventVisibility.shouldInclude(
                isCanceled: event.status == .canceled,
                isDeclinedByCurrentUser: isDeclined
            ) else { return nil }

            let color = NSColor(cgColor: event.calendar.cgColor)?.usingColorSpace(.sRGB)
            let stableID = "\(event.eventIdentifier ?? event.calendarItemIdentifier)-\(event.startDate.timeIntervalSinceReferenceDate)"
            let mapped = NightLoopCalendarEvent(
                id: stableID,
                title: event.title?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Untitled Event",
                startDate: event.startDate,
                endDate: event.endDate,
                isAllDay: event.isAllDay,
                calendarTitle: event.calendar.title,
                calendarColor: CalendarColorComponents(
                    red: Double(color?.redComponent ?? 0.55),
                    green: Double(color?.greenComponent ?? 0.28),
                    blue: Double(color?.blueComponent ?? 0.25),
                    alpha: Double(color?.alphaComponent ?? 1)
                )
            )
            return mapped.overlaps(range) ? mapped : nil
        }
        return CalendarEventOrdering.sort(events)
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
