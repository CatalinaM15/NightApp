import EventKit
import Foundation

struct ReminderList: Identifiable, Equatable {
    let id: String
    let title: String
    let account: String
    let isWritable: Bool
}

struct InboxReminder: Identifiable, Equatable {
    let id: String
    let title: String
    let notes: String
    let listID: String
    let dueDate: Date?
}

struct ReminderDraft {
    var title: String
    var notes = ""
    var listID: String
    var sourceNoteKey: String?

    func validatedTitle() throws -> String {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw ReminderInboxError.emptyTitle }
        return title
    }
}

enum ReminderInboxError: LocalizedError {
    case accessUnavailable, listUnavailable, readOnlyList, reminderUnavailable, emptyTitle, fetchFailed

    var errorDescription: String? {
        switch self {
        case .accessUnavailable: "Reminders access is unavailable. Check Privacy Settings."
        case .listUnavailable: "This list is unavailable. Choose a Reminders list."
        case .readOnlyList: "This list is read-only. Choose an editable list to save reminders."
        case .reminderUnavailable: "This reminder is no longer available. Refresh the Inbox."
        case .emptyTitle: "A reminder needs a title."
        case .fetchFailed: "Reminders could not be read. Please try Refresh."
        }
    }
}

@MainActor
protocol ReminderInboxStore {
    var authorizationStatus: EKAuthorizationStatus { get }
    func requestAccess() async throws
    func lists() -> [ReminderList]
    func reminders(in listID: String) async throws -> [InboxReminder]
    func save(_ draft: ReminderDraft, replacing identifier: String?) async throws
    func setCompleted(_ completed: Bool, identifier: String) throws
}

@MainActor
final class ReminderInboxService: ReminderInboxStore {
    private let eventStore: EKEventStore

    init(eventStore: EKEventStore = EKEventStore()) { self.eventStore = eventStore }

    var authorizationStatus: EKAuthorizationStatus { EKEventStore.authorizationStatus(for: .reminder) }

    func requestAccess() async throws { _ = try await eventStore.requestFullAccessToReminders() }

    func lists() -> [ReminderList] {
        guard authorizationStatus == .fullAccess else { return [] }
        return eventStore.calendars(for: .reminder).map {
            ReminderList(id: $0.calendarIdentifier, title: $0.title, account: $0.source.title, isWritable: $0.allowsContentModifications)
        }.sorted { ($0.account, $0.title) < ($1.account, $1.title) }
    }

    func reminders(in listID: String) async throws -> [InboxReminder] {
        let calendar = try list(listID, requiresWriting: false)
        let predicate = eventStore.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: [calendar])
        return try await fetch(predicate).map { reminder in
            InboxReminder(
                id: reminder.calendarItemIdentifier,
                title: reminder.title ?? "Untitled Reminder",
                notes: reminder.notes ?? "",
                listID: reminder.calendar.calendarIdentifier,
                dueDate: reminder.dueDateComponents.flatMap { ($0.calendar ?? Calendar.autoupdatingCurrent).date(from: $0) }
            )
        }
    }

    func save(_ draft: ReminderDraft, replacing identifier: String?) async throws {
        let title = try draft.validatedTitle()
        _ = try list(draft.listID, requiresWriting: true)
        if let sourceNoteKey = draft.sourceNoteKey {
            // A stable marker prevents duplicate note imports, even after a reminder is moved or completed.
            let predicate = eventStore.predicateForReminders(in: nil)
            let existing = try await fetch(predicate)
            if existing.contains(where: { $0.url == Self.noteURL(sourceNoteKey) }) { return }
        }
        let destination = try list(draft.listID, requiresWriting: true)
        let reminder: EKReminder
        if let identifier {
            reminder = try existingReminder(identifier)
            guard reminder.calendar.allowsContentModifications else { throw ReminderInboxError.readOnlyList }
        } else {
            reminder = EKReminder(eventStore: eventStore)
        }
        let previous = (reminder.title, reminder.notes, reminder.calendar, reminder.url)
        reminder.title = title
        reminder.notes = draft.notes.isEmpty ? nil : draft.notes
        reminder.calendar = destination
        if let sourceNoteKey = draft.sourceNoteKey { reminder.url = Self.noteURL(sourceNoteKey) }
        do { try eventStore.save(reminder, commit: true) }
        catch {
            reminder.title = previous.0
            reminder.notes = previous.1
            reminder.calendar = previous.2
            reminder.url = previous.3
            throw error
        }
    }

    func setCompleted(_ completed: Bool, identifier: String) throws {
        let reminder = try existingReminder(identifier)
        guard reminder.calendar.allowsContentModifications else { throw ReminderInboxError.readOnlyList }
        let previous = (reminder.isCompleted, reminder.completionDate)
        reminder.isCompleted = completed
        do { try eventStore.save(reminder, commit: true) }
        catch {
            reminder.isCompleted = previous.0
            reminder.completionDate = previous.1
            throw error
        }
    }

    private func list(_ identifier: String, requiresWriting: Bool) throws -> EKCalendar {
        guard authorizationStatus == .fullAccess else { throw ReminderInboxError.accessUnavailable }
        guard let calendar = eventStore.calendars(for: .reminder).first(where: { $0.calendarIdentifier == identifier }) else {
            throw ReminderInboxError.listUnavailable
        }
        guard !requiresWriting || calendar.allowsContentModifications else { throw ReminderInboxError.readOnlyList }
        return calendar
    }

    private func existingReminder(_ identifier: String) throws -> EKReminder {
        guard authorizationStatus == .fullAccess else { throw ReminderInboxError.accessUnavailable }
        guard let reminder = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder else {
            throw ReminderInboxError.reminderUnavailable
        }
        return reminder
    }

    private func fetch(_ predicate: NSPredicate) async throws -> [EKReminder] {
        try await withCheckedThrowingContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                if let reminders { continuation.resume(returning: reminders) }
                else { continuation.resume(throwing: ReminderInboxError.fetchFailed) }
            }
        }
    }

    static func noteURL(_ key: String) -> URL {
        URL(string: "homebase://previous-note/")!.appendingPathComponent(key)
    }
}
