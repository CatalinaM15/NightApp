import Foundation
import SwiftData

extension NightLoopSchemaV4 {
@Model final class RoutineCompletion {
    @Attribute(.unique) var id: UUID
    var dayKey: String
    var completedAt: Date
    var timeZoneIdentifier: String
    var routine: Routine?

    init(
        id: UUID = UUID(),
        dayKey: String,
        completedAt: Date,
        timeZoneIdentifier: String,
        routine: Routine? = nil
    ) {
        self.id = id
        self.dayKey = dayKey
        self.completedAt = completedAt
        self.timeZoneIdentifier = timeZoneIdentifier
        self.routine = routine
    }
}
}

typealias RoutineCompletion = NightLoopSchemaV4.RoutineCompletion
