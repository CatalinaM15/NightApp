import Foundation
import SwiftData

enum RoutineStoreError: LocalizedError, Equatable {
    case emptyTitle
    case duplicateTitle
    case activeRoutineLimit
    case groupedRoutineNeedsStep
    case emptyStepTitle
    case invalidStepSchedule
    case invalidStepLink

    var errorDescription: String? {
        switch self {
        case .emptyTitle: "A routine needs a title."
        case .duplicateTitle: "A routine with this title already exists."
        case .activeRoutineLimit: "HomeBase supports up to seven active routines. Disable one before adding or reactivating another."
        case .groupedRoutineNeedsStep: "A grouped routine needs at least one step."
        case .emptyStepTitle: "Every grouped routine step needs a title."
        case .invalidStepSchedule: "Choose at least one weekday for each Daily step."
        case .invalidStepLink: "Daily steps can link to Exercise or Body Care."
        }
    }
}

struct RoutineStepDraft: Identifiable, Equatable {
    let id: UUID
    var title: String
    var carePeriod: DailyCarePeriod?
    var dailySchedule: DailyStepScheduleDraft?

    init(id: UUID = UUID(), title: String = "", carePeriod: DailyCarePeriod? = nil, dailySchedule: DailyStepScheduleDraft? = nil) {
        self.id = id
        self.title = title
        self.carePeriod = carePeriod
        self.dailySchedule = dailySchedule
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
        let protectedSteps = try preservingDailyExercise(steps, for: routine, in: context)
        let normalizedSteps = try validatedSteps(protectedSteps, isGrouped: routine.isGrouped)
        routine.title = try validatedTitle(title, excluding: routine.id, in: context)
        routine.iconName = iconName
        routine.scheduledWeekdaysMask = scheduledWeekdaysMask
        try reconcileSteps(normalizedSteps, for: routine, in: context)
        if routine.cardSlot == 4 {
            try RoutineGroupCompletionStore.synchronizeDailyCompletion(for: routine, on: .now, in: context)
        }
        try context.save()
    }

    @discardableResult
    static func ensureDailyExercise(_ routine: Routine, on date: Date = .now, in context: ModelContext) throws -> NightRoutineStep {
        guard routine.cardSlot == 4 else { throw RoutineStoreError.invalidStepLink }
        let links = try context.fetch(FetchDescriptor<DailyStepActivityLink>())
        let ordered = routine.steps.sorted { $0.order < $1.order }
        let existing = ordered.first { step in
            step.title == "Exercise" && links.contains { $0.stepID == step.id && $0.category == RotatingCardCategory.exercise.rawValue }
        } ?? ordered.first { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("Exercise") == .orderedSame }
            ?? ordered.first { DailyStepActivityLink.category(for: $0, in: links) == .exercise }
        let exercise: NightRoutineStep
        if let existing { exercise = existing }
        else {
            exercise = NightRoutineStep(title: "Exercise", order: (ordered.map(\.order).max() ?? -1) + 1, routine: routine)
            context.insert(exercise)
        }
        exercise.title = "Exercise"
        if let link = links.first(where: { $0.stepID == exercise.id }) { link.category = RotatingCardCategory.exercise.rawValue }
        else { context.insert(DailyStepActivityLink(stepID: exercise.id, category: .exercise)) }
        for step in ordered where step.id != exercise.id && DailyStepActivityLink.category(for: step, in: links) == .exercise {
            if let link = links.first(where: { $0.stepID == step.id }) { link.category = nil }
            else { context.insert(DailyStepActivityLink(stepID: step.id, category: nil)) }
        }
        let groups = try context.fetch(FetchDescriptor<DailyCareStepGroup>())
        if !groups.contains(where: { $0.stepID == exercise.id }) {
            context.insert(DailyCareStepGroup(stepID: exercise.id, period: .morning))
        }
        let schedules = try context.fetch(FetchDescriptor<DailyStepSchedule>())
        if let schedule = schedules.first(where: { $0.stepID == exercise.id }) { schedule.weekdaysMask = RoutineSchedule.allDaysMask }
        else { context.insert(DailyStepSchedule(stepID: exercise.id, draft: DailyStepScheduleDraft(linkedCategory: .exercise))) }
        try RoutineGroupCompletionStore.synchronizeDailyCompletion(for: routine, on: date, in: context)
        try context.save()
        return exercise
    }

    private static func preservingDailyExercise(_ drafts: [RoutineStepDraft], for routine: Routine, in context: ModelContext) throws -> [RoutineStepDraft] {
        guard routine.cardSlot == 4 else { return drafts }
        let links = try context.fetch(FetchDescriptor<DailyStepActivityLink>())
        guard let exercise = routine.steps.first(where: { step in
            step.title == "Exercise" && links.contains { $0.stepID == step.id && $0.category == RotatingCardCategory.exercise.rawValue }
        }) else { return drafts }
        let groups = try context.fetch(FetchDescriptor<DailyCareStepGroup>())
        let schedules = try context.fetch(FetchDescriptor<DailyStepSchedule>())
        var schedule = DailyStepSchedule.draft(for: exercise.id, in: schedules)
        schedule.linkedCategory = .exercise
        schedule.weekdaysMask = RoutineSchedule.allDaysMask
        let index = drafts.firstIndex { $0.id == exercise.id }
        let period = index.flatMap { drafts[$0].carePeriod } ?? DailyCareStepGroup.period(for: exercise.id, in: groups)
        let fixed = RoutineStepDraft(id: exercise.id, title: "Exercise", carePeriod: period, dailySchedule: schedule)
        var result = drafts
        if let index { result[index] = fixed }
        else { result.insert(fixed, at: min(exercise.order, result.count)) }
        return result
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
            var schedule = draft.dailySchedule
            if var value = schedule {
                guard value.linkedCategory != .hobby else { throw RoutineStoreError.invalidStepLink }
                guard value.weekdaysMask != 0, value.weekdaysMask & ~RoutineSchedule.allDaysMask == 0,
                      value.variations.count == 7 else { throw RoutineStoreError.invalidStepSchedule }
                value.variations = value.variations.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                schedule = value
            }
            return RoutineStepDraft(id: draft.id, title: title, carePeriod: draft.carePeriod, dailySchedule: schedule)
        }
    }

    private static func reconcileSteps(
        _ drafts: [RoutineStepDraft],
        for routine: Routine,
        in context: ModelContext
    ) throws {
        guard routine.isGrouped else { return }
        let draftsByID = Dictionary(uniqueKeysWithValues: drafts.map { ($0.id, $0) })
        let groups = routine.cardSlot == 4 ? try context.fetch(FetchDescriptor<DailyCareStepGroup>()) : []
        let removedIDs = Set(routine.steps.filter { draftsByID[$0.id] == nil }.map(\.id))
        groups.filter { removedIDs.contains($0.stepID) }.forEach(context.delete)
        let schedules = routine.cardSlot == 4 ? try context.fetch(FetchDescriptor<DailyStepSchedule>()) : []
        schedules.filter { removedIDs.contains($0.stepID) }.forEach(context.delete)
        let links = routine.cardSlot == 4 ? try context.fetch(FetchDescriptor<DailyStepActivityLink>()) : []
        links.filter { removedIDs.contains($0.stepID) }.forEach(context.delete)
        for draft in drafts {
            guard let schedule = draft.dailySchedule, routine.cardSlot == 4 else { continue }
            if let existing = links.first(where: { $0.stepID == draft.id }) {
                existing.category = schedule.linkedCategory?.rawValue
            } else {
                context.insert(DailyStepActivityLink(stepID: draft.id, category: schedule.linkedCategory))
            }
            if let existing = schedules.first(where: { $0.stepID == draft.id }) {
                existing.weekdaysMask = schedule.weekdaysMask
                existing.variations = schedule.variations
            } else {
                context.insert(DailyStepSchedule(stepID: draft.id, draft: schedule))
            }
        }
        for draft in drafts {
            guard let period = draft.carePeriod, routine.cardSlot == 4 else { continue }
            if let existing = groups.first(where: { $0.stepID == draft.id }) {
                existing.period = period.rawValue
            } else {
                context.insert(DailyCareStepGroup(stepID: draft.id, period: period))
            }
        }
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
