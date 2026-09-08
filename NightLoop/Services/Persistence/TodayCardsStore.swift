import Foundation
import SwiftData

enum TodayCardsStoreError: LocalizedError {
    case invalidExperimentSlot
    case occupiedExperimentSlot
    case optionNameRequired
    case duplicateOption

    var errorDescription: String? {
        switch self {
        case .invalidExperimentSlot: "Choose an Experiment slot from 1 through 3."
        case .occupiedExperimentSlot: "That Experiment slot is already in use."
        case .optionNameRequired: "An option needs a name."
        case .duplicateOption: "That option already exists."
        }
    }
}

@MainActor
enum TodayCardsStore {
    static func bootstrap(in context: ModelContext, date: Date = .now) throws {
        var routines = try context.fetch(FetchDescriptor<Routine>())
        let isConfigured = routines.contains { $0.cardSlot == 4 }

        if !isConfigured {
            let legacyExperiments = routines
                .filter(\.isGrouped)
                .sorted { ($0.sortOrder, $0.title) < ($1.sortOrder, $1.title) }
                .prefix(3)

            for (index, routine) in legacyExperiments.enumerated() {
                routine.cardSlot = index + 5
                routine.isActive = true
                routine.scheduledWeekdaysMask = RoutineSchedule.allDaysMask
                routine.sortOrder = index
            }

            let retainedIDs = Set(legacyExperiments.map(\.id))
            routines.filter { !retainedIDs.contains($0.id) }.forEach(context.delete)

            let dailyCare = Routine(
                title: "Daily Care",
                iconName: "heart.text.square",
                sortOrder: 0,
                activePeriodStartedDayKey: CivilDay(date: date).key,
                scheduledWeekdaysMask: RoutineSchedule.allDaysMask,
                isGrouped: true,
                cardSlot: 4
            )
            context.insert(dailyCare)
            context.insert(NightRoutineStep(title: "Body Cream", order: 0, routine: dailyCare))
            context.insert(NightRoutineStep(title: "Skincare", order: 1, routine: dailyCare))
            routines = try context.fetch(FetchDescriptor<Routine>())
        }

        let options = try context.fetch(FetchDescriptor<CardOption>())
        for category in RotatingCardCategory.allCases where !options.contains(where: { $0.category == category.rawValue }) {
            for (index, name) in category.initialOptions.enumerated() {
                context.insert(CardOption(category: category, name: name, sortOrder: index))
            }
        }
        try context.save()
    }

    static func routine(forSlot slot: Int, in routines: [Routine]) -> Routine? {
        routines.first { $0.cardSlot == slot }
    }

    static func options(for category: RotatingCardCategory, in options: [CardOption]) -> [CardOption] {
        options.filter { $0.category == category.rawValue }.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }

    @discardableResult
    static func resolveSelection(
        category: RotatingCardCategory,
        on date: Date,
        options: [CardOption],
        history: [SlotSelectionHistory],
        calendar: Calendar = .autoupdatingCurrent,
        in context: ModelContext
    ) throws -> SlotSelectionHistory? {
        let day = calendar.startOfDay(for: date)
        if let existing = history.first(where: {
            $0.category == category.rawValue && calendar.isDate($0.date, inSameDayAs: day)
        }) { return existing }

        guard let weekday = RoutineWeekday(calendarWeekday: calendar.component(.weekday, from: day)) else { return nil }
        guard let defaultOption = Self.options(for: category, in: options).first(where: {
            RoutineSchedule.contains(weekday, in: $0.scheduledWeekdaysMask)
        }) else { return nil }

        let selection = SlotSelectionHistory(category: category, optionName: defaultOption.name, date: day, calendar: calendar)
        context.insert(selection)
        try context.save()
        return selection
    }

    @discardableResult
    static func choose(
        _ option: CardOption,
        category: RotatingCardCategory,
        on date: Date,
        history: [SlotSelectionHistory],
        calendar: Calendar = .autoupdatingCurrent,
        in context: ModelContext
    ) throws -> SlotSelectionHistory {
        let day = calendar.startOfDay(for: date)
        if let existing = history.first(where: {
            $0.category == category.rawValue && calendar.isDate($0.date, inSameDayAs: day)
        }) {
            existing.optionName = option.name
            existing.completedAt = nil
            try context.save()
            return existing
        }
        let selection = SlotSelectionHistory(category: category, optionName: option.name, date: day, calendar: calendar)
        context.insert(selection)
        try context.save()
        return selection
    }

    static func complete(_ selection: SlotSelectionHistory, at date: Date = .now, in context: ModelContext) throws {
        guard selection.completedAt == nil else { return }
        selection.completedAt = date
        try context.save()
    }

    static func undoCompletion(_ selection: SlotSelectionHistory, in context: ModelContext) throws {
        selection.completedAt = nil
        try context.save()
    }

    static func toggleCompletion(
        _ selection: SlotSelectionHistory,
        at date: Date = .now,
        in context: ModelContext
    ) throws {
        selection.completedAt = selection.completedAt == nil ? date : nil
        try context.save()
    }

    static func daysSinceLastPicked(
        option: CardOption,
        before date: Date,
        history: [SlotSelectionHistory],
        calendar: Calendar = .autoupdatingCurrent
    ) -> Int? {
        let day = calendar.startOfDay(for: date)
        guard let latest = (history
            .filter { $0.category == option.category && $0.optionName == option.name && $0.date < day }
            .max(by: { $0.date < $1.date })) else { return nil }
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: latest.date), to: day).day
    }

    static func setDefault(
        option: CardOption,
        weekday: RoutineWeekday,
        selected: Bool,
        allOptions: [CardOption],
        in context: ModelContext
    ) throws {
        if selected {
            for other in allOptions where other.category == option.category && other.id != option.id {
                other.scheduledWeekdaysMask &= ~weekday.bit
            }
            option.scheduledWeekdaysMask |= weekday.bit
        } else {
            option.scheduledWeekdaysMask &= ~weekday.bit
        }
        try context.save()
    }

    static func addOption(
        named name: String,
        category: RotatingCardCategory,
        allOptions: [CardOption],
        in context: ModelContext
    ) throws {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw TodayCardsStoreError.optionNameRequired }
        let categoryOptions = options(for: category, in: allOptions)
        guard !categoryOptions.contains(where: { $0.name.compare(normalized, options: .caseInsensitive) == .orderedSame }) else {
            throw TodayCardsStoreError.duplicateOption
        }
        context.insert(CardOption(
            category: category,
            name: normalized,
            sortOrder: (categoryOptions.map(\.sortOrder).max() ?? -1) + 1
        ))
        try context.save()
    }

    static func renameHobbyOption(
        _ option: CardOption,
        to name: String,
        allOptions: [CardOption],
        history: [SlotSelectionHistory],
        in context: ModelContext
    ) throws {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw TodayCardsStoreError.optionNameRequired }
        guard !options(for: .hobby, in: allOptions).contains(where: {
            $0.id != option.id && $0.name.compare(normalized, options: .caseInsensitive) == .orderedSame
        }) else { throw TodayCardsStoreError.duplicateOption }
        let oldName = option.name
        option.name = normalized
        history.filter { $0.category == option.category && $0.optionName == oldName }.forEach { $0.optionName = normalized }
        try context.save()
    }

    static func updateOption(
        _ option: CardOption,
        name: String,
        scheduledWeekdaysMask: Int,
        allOptions: [CardOption],
        history: [SlotSelectionHistory],
        in context: ModelContext
    ) throws {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw TodayCardsStoreError.optionNameRequired }
        guard !allOptions.contains(where: {
            $0.category == option.category && $0.id != option.id &&
            $0.name.compare(normalized, options: .caseInsensitive) == .orderedSame
        }) else { throw TodayCardsStoreError.duplicateOption }

        for weekday in RoutineWeekday.allCases where RoutineSchedule.contains(weekday, in: scheduledWeekdaysMask) {
            for other in allOptions where other.category == option.category && other.id != option.id {
                other.scheduledWeekdaysMask &= ~weekday.bit
            }
        }

        let oldName = option.name
        option.name = normalized
        option.scheduledWeekdaysMask = scheduledWeekdaysMask
        history.filter { $0.category == option.category && $0.optionName == oldName }.forEach {
            $0.optionName = normalized
        }
        try context.save()
    }

    static func createExperiment(
        number: Int,
        title: String,
        iconName: String,
        steps: [RoutineStepDraft],
        on date: Date,
        in context: ModelContext
    ) throws {
        guard (1...3).contains(number) else { throw TodayCardsStoreError.invalidExperimentSlot }
        let slot = number + 4
        let routines = try context.fetch(FetchDescriptor<Routine>())
        guard routine(forSlot: slot, in: routines) == nil else { throw TodayCardsStoreError.occupiedExperimentSlot }
        let created = try RoutineStore.create(
            title: title,
            iconName: iconName,
            isGrouped: true,
            steps: steps,
            on: date,
            in: context
        )
        created.cardSlot = slot
        created.scheduledWeekdaysMask = RoutineSchedule.allDaysMask
        try context.save()
    }

    @discardableResult
    static func archiveExperiment(
        _ routine: Routine,
        on date: Date = .now,
        calendar: Calendar = .autoupdatingCurrent,
        in context: ModelContext
    ) throws -> ExperimentArchiveRecord {
        guard let slot = routine.cardSlot, (5...7).contains(slot) else { throw TodayCardsStoreError.invalidExperimentSlot }
        let completionDays = Set(routine.steps.flatMap(\.completions).map { calendar.startOfDay(for: $0.date) })
        let fallbackStart = dateFromDayKey(routine.activePeriodStartedDayKey, calendar: calendar) ?? date
        let record = ExperimentArchiveRecord(
            name: routine.title,
            totalActiveDays: completionDays.count,
            startDate: fallbackStart,
            endDate: calendar.startOfDay(for: date),
            sourceSlot: slot
        )
        context.insert(record)
        context.delete(routine)
        try context.save()
        return record
    }

    private static func dateFromDayKey(_ key: String, calendar: Calendar) -> Date? {
        let values = key.split(separator: "-").compactMap { Int($0) }
        guard values.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: values[0], month: values[1], day: values[2]))
    }
}
