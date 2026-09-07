import Foundation
import SwiftData

enum RoutineStoreError: LocalizedError, Equatable {
    case emptyTitle
    case duplicateTitle
    case activeRoutineLimit
    case groupedRoutineNeedsStep
    case emptyStepTitle

    var errorDescription: String? {
        switch self {
        case .emptyTitle: "A routine needs a title."
        case .duplicateTitle: "A routine with this title already exists."
        case .activeRoutineLimit: "NightLoop supports up to seven active routines. Disable one before adding or reactivating another."
        case .groupedRoutineNeedsStep: "A grouped routine needs at least one step."
        case .emptyStepTitle: "Every grouped routine step needs a title."
        }
    }
}

struct RoutineStepDraft: Identifiable, Equatable {
    let id: UUID
    var title: String

    init(id: UUID = UUID(), title: String = "") {
        self.id = id
        self.title = title
    }
}

@MainActor
enum RoutineStore {
    @discardableResult
    static func create(
        title: String,
        iconName: String,
        scheduledWeekdaysMask: Int = RoutineSchedule.allDaysMask,
        isGrouped: Bool = false,
        steps: [RoutineStepDraft] = [],
        on date: Date = .now,
        calendar: Calendar = .autoupdatingCurrent,
        in context: ModelContext
    ) throws -> Routine {
        let normalizedTitle = try validatedTitle(title, excluding: nil, in: context)
        let routines = try context.fetch(FetchDescriptor<Routine>())
        guard routines.filter(\.isActive).count < 7 else { throw RoutineStoreError.activeRoutineLimit }
        let normalizedSteps = try validatedSteps(steps, isGrouped: isGrouped)
        let nextOrder = (routines.map(\.sortOrder).max() ?? -1) + 1
        let routine = Routine(
            title: normalizedTitle,
            iconName: iconName,
            sortOrder: nextOrder,
            activePeriodStartedDayKey: CivilDay(date: date, calendar: calendar).key,
            scheduledWeekdaysMask: scheduledWeekdaysMask,
            isGrouped: isGrouped
        )
        context.insert(routine)
        for (index, draft) in normalizedSteps.enumerated() {
            context.insert(NightRoutineStep(id: draft.id, title: draft.title, order: index, routine: routine))
        }
        try context.save()
        return routine
    }

    static func update(
        _ routine: Routine,
        title: String,
        iconName: String,
        scheduledWeekdaysMask: Int = RoutineSchedule.allDaysMask,
        steps: [RoutineStepDraft] = [],
        in context: ModelContext
    ) throws {
        let normalizedSteps = try validatedSteps(steps, isGrouped: routine.isGrouped)
        routine.title = try validatedTitle(title, excluding: routine.id, in: context)
        routine.iconName = iconName
        routine.scheduledWeekdaysMask = scheduledWeekdaysMask
        try reconcileSteps(normalizedSteps, for: routine, in: context)
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
        let activeCount = try context.fetch(FetchDescriptor<Routine>()).filter(\.isActive).count
        guard activeCount < 7 else { throw RoutineStoreError.activeRoutineLimit }
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

    private static func validatedSteps(
        _ drafts: [RoutineStepDraft],
        isGrouped: Bool
    ) throws -> [RoutineStepDraft] {
        guard isGrouped else { return [] }
        guard !drafts.isEmpty else { throw RoutineStoreError.groupedRoutineNeedsStep }
        return try drafts.map { draft in
            let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { throw RoutineStoreError.emptyStepTitle }
            return RoutineStepDraft(id: draft.id, title: title)
        }
    }

    private static func reconcileSteps(
        _ drafts: [RoutineStepDraft],
        for routine: Routine,
        in context: ModelContext
    ) throws {
        guard routine.isGrouped else { return }
        let draftsByID = Dictionary(uniqueKeysWithValues: drafts.map { ($0.id, $0) })
        for existing in routine.steps where draftsByID[existing.id] == nil {
            context.delete(existing)
        }

        let existingByID = Dictionary(uniqueKeysWithValues: routine.steps.map { ($0.id, $0) })
        for (index, draft) in drafts.enumerated() {
            if let existing = existingByID[draft.id] {
                existing.title = draft.title
                existing.order = index
            } else {
                context.insert(NightRoutineStep(id: draft.id, title: draft.title, order: index, routine: routine))
            }
        }
    }
}
