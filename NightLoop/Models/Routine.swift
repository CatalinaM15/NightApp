import Foundation
import SwiftData

@Model
final class Routine {
    @Attribute(.unique) var id: UUID
    var title: String
    var iconName: String
    var sortOrder: Int
    var isActive: Bool
    var activePeriodStartedDayKey: String

    @Relationship(deleteRule: .cascade, inverse: \RoutineCompletion.routine)
    var completions: [RoutineCompletion]

    init(
        id: UUID = UUID(),
        title: String,
        iconName: String = "moon.stars",
        sortOrder: Int = 0,
        isActive: Bool = true,
        activePeriodStartedDayKey: String = CivilDay(date: .now).key
    ) {
        self.id = id
        self.title = title
        self.iconName = iconName
        self.sortOrder = sortOrder
        self.isActive = isActive
        self.activePeriodStartedDayKey = activePeriodStartedDayKey
        self.completions = []
    }
}
