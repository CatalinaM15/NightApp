import Foundation
import SwiftData

enum RoutineStoreError: LocalizedError, Equatable {
    case emptyTitle
    case duplicateTitle

    var errorDescription: String? {
        switch self {
        case .emptyTitle: "A routine needs a title."
        case .duplicateTitle: "A routine with this title already exists."
        }
    }
}

@MainActor
enum RoutineStore {
    static func create(
        title: String,
        iconName: String,
        on date: Date = .now,
        calendar: Calendar = .autoupdatingCurrent,
        in context: ModelContext
    ) throws {
        let normalizedTitle = try validatedTitle(title, excluding: nil, in: context)
        let routines = try context.fetch(FetchDescriptor<Routine>())
        let nextOrder = (routines.map(\.sortOrder).max() ?? -1) + 1
        context.insert(Routine(
            title: normalizedTitle,
            iconName: iconName,
            sortOrder: nextOrder,
            activePeriodStartedDayKey: CivilDay(date: date, calendar: calendar).key
        ))
        try context.save()
    }

    static func update(
        _ routine: Routine,
        title: String,
        iconName: String,
        in context: ModelContext
    ) throws {
        routine.title = try validatedTitle(title, excluding: routine.id, in: context)
        routine.iconName = iconName
        try context.save()
    }

    static func disable(_ routine: Routine, in context: ModelContext) throws {
        routine.isActive = false
        try context.save()
    }

    static func reactivate(
        _ routine: Routine,
        on date: Date = .now,
        calendar: Calendar = .autoupdatingCurrent,
        in context: ModelContext
    ) throws {
        routine.isActive = true
        routine.activePeriodStartedDayKey = CivilDay(date: date, calendar: calendar).key
        routine.sortOrder = try context.fetch(FetchDescriptor<Routine>())
            .filter(\.isActive)
            .map(\.sortOrder)
            .max()
            .map { $0 + 1 } ?? 0
        try context.save()
    }

    static func move(
        _ routine: Routine,
        by offset: Int,
        in context: ModelContext
    ) throws {
        var active = try context.fetch(FetchDescriptor<Routine>())
            .filter(\.isActive)
            .sorted { ($0.sortOrder, $0.title) < ($1.sortOrder, $1.title) }
        guard let source = active.firstIndex(where: { $0.id == routine.id }) else { return }
        let destination = source + offset
        guard active.indices.contains(destination) else { return }
        active.swapAt(source, destination)
        for (index, item) in active.enumerated() { item.sortOrder = index }
        try context.save()
    }

    private static func validatedTitle(
        _ title: String,
        excluding id: UUID?,
        in context: ModelContext
    ) throws -> String {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw RoutineStoreError.emptyTitle }
        let routines = try context.fetch(FetchDescriptor<Routine>())
        guard !routines.contains(where: {
            $0.id != id && $0.title.compare(normalized, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) else { throw RoutineStoreError.duplicateTitle }
        return normalized
    }
}
