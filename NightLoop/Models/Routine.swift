import Foundation
import SwiftData

extension NightLoopSchemaV4 {
@Model final class Routine {
    @Attribute(.unique) var id: UUID
    var title: String
    var iconName: String
    var sortOrder: Int
    var isActive: Bool
    var activePeriodStartedDayKey: String
    var scheduledWeekdaysMask: Int = RoutineSchedule.allDaysMask
    var isGrouped: Bool = false
    var cardSlot: Int?

    @Relationship(deleteRule: .cascade, inverse: \RoutineCompletion.routine)
    var completions: [RoutineCompletion]
    @Relationship(deleteRule: .cascade, inverse: \NightRoutineStep.routine)
    var steps: [NightRoutineStep]

    init(
        id: UUID = UUID(),
        title: String,
        iconName: String = "moon.stars",
        sortOrder: Int = 0,
        isActive: Bool = true,
        activePeriodStartedDayKey: String = CivilDay(date: .now).key,
        scheduledWeekdaysMask: Int = RoutineSchedule.allDaysMask,
        isGrouped: Bool = false,
        cardSlot: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.iconName = iconName
        self.sortOrder = sortOrder
        self.isActive = isActive
        self.activePeriodStartedDayKey = activePeriodStartedDayKey
        self.scheduledWeekdaysMask = scheduledWeekdaysMask
        self.isGrouped = isGrouped
        self.cardSlot = cardSlot
        self.completions = []
        self.steps = []
    }

    func isScheduled(on date: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        RoutineSchedule.includes(date: date, mask: scheduledWeekdaysMask, calendar: calendar)
    }
}
}

typealias Routine = NightLoopSchemaV4.Routine
