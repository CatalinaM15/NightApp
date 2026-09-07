import Foundation
import SwiftData

extension NightLoopSchemaV4 {
@Model final class NightRoutineStepCompletion {
    @Attribute(.unique) var id: UUID
    var date: Date
    var step: NightRoutineStep?

    init(
        id: UUID = UUID(),
        date: Date,
        step: NightRoutineStep,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.id = id
        self.date = calendar.startOfDay(for: date)
        self.step = step
    }
}
}

typealias NightRoutineStepCompletion = NightLoopSchemaV4.NightRoutineStepCompletion
