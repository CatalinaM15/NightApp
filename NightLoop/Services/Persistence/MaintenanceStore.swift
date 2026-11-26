import Foundation
import SwiftData

enum MaintenanceStoreError: LocalizedError, Equatable {
    case emptyTitle, invalidSchedule, futureDate, duplicateDate

    var errorDescription: String? {
        switch self {
        case .emptyTitle: "Enter a name before saving."
        case .invalidSchedule: "Choose a supported frequency and a weekday for weekly chores."
        case .futureDate: "Choose today or an earlier date."
        case .duplicateDate: "This date is already in the history."
        }
    }
}

struct MaintenanceWeekChange {
    var addedIDs: [UUID] = []
    var removed: [(id: UUID, date: Date)] = []
}

@MainActor
enum MaintenanceStore {
    @discardableResult
    static func create(
        title: String, kind: MaintenanceKind, frequency: MaintenanceFrequency,
        weekday: Int? = nil, lastDate: Date? = nil, now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent, in context: ModelContext
    ) throws -> MaintenanceItem {
        try createBatch(titles: [title], kind: kind, frequency: frequency, weekday: weekday,
                        lastDate: lastDate, now: now, calendar: calendar, in: context)[0]
    }

    static func batchTitles(from text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    @discardableResult
    static func createBatch(
        titles: [String], kind: MaintenanceKind, frequency: MaintenanceFrequency,
        weekday: Int? = nil, lastDate: Date? = nil, now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent, in context: ModelContext
    ) throws -> [MaintenanceItem] {
        try createBatch(entries: titles.map { MaintenanceBatchEntry(title: $0, frequency: frequency, weekday: weekday) },
                        kind: kind, lastDate: lastDate, now: now, calendar: calendar, in: context)
    }

    @discardableResult
    static func createBatch(
        entries: [MaintenanceBatchEntry], kind: MaintenanceKind,
        lastDate: Date? = nil, now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent, in context: ModelContext
    ) throws -> [MaintenanceItem] {
        guard !entries.isEmpty else { throw MaintenanceStoreError.emptyTitle }
        let normalized = try entries.map { entry in
            MaintenanceBatchEntry(title: try validatedTitle(entry.title), frequency: entry.frequency,
                                  weekday: try validatedWeekday(entry.weekday, kind: kind, frequency: entry.frequency))
        }
        let date = try lastDate.map { try validatedDate($0, now: now, calendar: calendar) }
        let items = normalized.map { MaintenanceItem(title: $0.title, kind: kind, frequency: $0.frequency, weekday: $0.weekday) }
        try context.transaction {
            for item in items {
                context.insert(item)
                if let date { context.insert(MaintenanceRecord(date: date, item: item)) }
            }
            try context.save()
        }
        return items
    }

    static func update(
        _ item: MaintenanceItem, title: String, frequency: MaintenanceFrequency,
        weekday: Int? = nil, in context: ModelContext
    ) throws {
        let name = try validatedTitle(title)
        guard let kind = MaintenanceKind(rawValue: item.kind) else { throw MaintenanceStoreError.invalidSchedule }
        let day = try validatedWeekday(weekday, kind: kind, frequency: frequency)
        item.title = name
        item.frequency = frequency.rawValue
        item.weekday = day
        try context.save()
    }

    @discardableResult
    static func record(
        _ item: MaintenanceItem, on date: Date, now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent, in context: ModelContext
    ) throws -> MaintenanceRecord {
        let day = try validatedDate(date, now: now, calendar: calendar)
        guard !item.isRecorded(on: day, calendar: calendar) else { throw MaintenanceStoreError.duplicateDate }
        let record = MaintenanceRecord(date: day, item: item)
        context.insert(record)
        try context.save()
        return record
    }

    static func updateDate(
        _ record: MaintenanceRecord, to date: Date, now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent, in context: ModelContext
    ) throws {
        let day = try validatedDate(date, now: now, calendar: calendar)
        guard record.item?.records.contains(where: {
            $0.id != record.id && calendar.isDate($0.date, inSameDayAs: day)
        }) != true else { throw MaintenanceStoreError.duplicateDate }
        record.date = day
        try context.save()
    }

    static func removeRecord(id: UUID, in context: ModelContext) throws {
        let descriptor = FetchDescriptor<MaintenanceRecord>(predicate: #Predicate { $0.id == id })
        guard let record = try context.fetch(descriptor).first else { return }
        context.delete(record)
        try context.save()
    }

    static func delete(_ item: MaintenanceItem, in context: ModelContext) throws {
        context.delete(item)
        try context.save()
    }

    static func chores(on date: Date, among items: [MaintenanceItem], calendar: Calendar = .autoupdatingCurrent) -> [MaintenanceItem] {
        guard let weekday = RoutineWeekday(calendarWeekday: calendar.component(.weekday, from: date)) else { return [] }
        return items.filter {
            $0.kind == MaintenanceKind.chores.rawValue && $0.frequency == MaintenanceFrequency.weekly.rawValue && $0.weekday == weekday.rawValue
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    static func setWeeklyCompletion(
        _ completed: Bool, for item: MaintenanceItem, on date: Date, now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent, in context: ModelContext
    ) throws -> MaintenanceWeekChange {
        guard item.kind == MaintenanceKind.chores.rawValue, item.frequency == MaintenanceFrequency.weekly.rawValue,
              let range = calendar.weekRange(containing: date) else { throw MaintenanceStoreError.invalidSchedule }
        if completed {
            guard !item.isRecordedThisWeek(on: date, calendar: calendar) else { return MaintenanceWeekChange() }
            let record = try record(item, on: date, now: now, calendar: calendar, in: context)
            return MaintenanceWeekChange(addedIDs: [record.id])
        }
        let records = item.records.filter { range.contains($0.date) }
        let change = MaintenanceWeekChange(removed: records.map { ($0.id, $0.date) })
        try context.transaction {
            records.forEach(context.delete)
            try context.save()
        }
        return change
    }

    static func undoWeeklyCompletion(_ change: MaintenanceWeekChange, for item: MaintenanceItem, in context: ModelContext) throws {
        try context.transaction {
            item.records.filter { change.addedIDs.contains($0.id) }.forEach(context.delete)
            for record in change.removed where !item.records.contains(where: { $0.id == record.id }) {
                context.insert(MaintenanceRecord(id: record.id, date: record.date, item: item))
            }
            try context.save()
        }
    }

    private static func validatedTitle(_ title: String) throws -> String {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw MaintenanceStoreError.emptyTitle }
        return normalized
    }

    private static func validatedWeekday(_ weekday: Int?, kind: MaintenanceKind, frequency: MaintenanceFrequency) throws -> Int? {
        guard kind.frequencies.contains(frequency) else { throw MaintenanceStoreError.invalidSchedule }
        guard frequency == .weekly else { return nil }
        guard let weekday, RoutineWeekday(rawValue: weekday) != nil else { throw MaintenanceStoreError.invalidSchedule }
        return weekday
    }

    private static func validatedDate(_ date: Date, now: Date, calendar: Calendar) throws -> Date {
        guard date.timeIntervalSinceReferenceDate.isFinite,
              calendar.startOfDay(for: date) <= calendar.startOfDay(for: now) else { throw MaintenanceStoreError.futureDate }
        return calendar.startOfDay(for: date)
    }
}
