import Foundation
import SwiftData

@MainActor
enum DailyNoteStore {
    static func note(
        on date: Date,
        among notes: [DailyNote],
        calendar: Calendar = .autoupdatingCurrent
    ) -> DailyNote? {
        notes.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    @discardableResult
    static func setText(
        _ text: String,
        on date: Date,
        calendar: Calendar = .autoupdatingCurrent,
        in context: ModelContext
    ) throws -> DailyNote {
        let notes = try context.fetch(FetchDescriptor<DailyNote>())
        if let existing = note(on: date, among: notes, calendar: calendar) {
            existing.text = text
            try context.save()
            return existing
        }
        let created = DailyNote(date: date, text: text, calendar: calendar)
        context.insert(created)
        try context.save()
        return created
    }

    static func text(
        on date: Date,
        calendar: Calendar = .autoupdatingCurrent,
        in context: ModelContext
    ) throws -> String {
        note(on: date, among: try context.fetch(FetchDescriptor<DailyNote>()), calendar: calendar)?.text ?? ""
    }

    static func pruneNotes(
        before date: Date,
        calendar: Calendar = .autoupdatingCurrent,
        in context: ModelContext
    ) throws {
        let today = calendar.startOfDay(for: date)
        let expired = try context.fetch(FetchDescriptor<DailyNote>()).filter { $0.date < today }
        guard !expired.isEmpty else { return }
        expired.forEach(context.delete)
        try context.save()
    }
}
