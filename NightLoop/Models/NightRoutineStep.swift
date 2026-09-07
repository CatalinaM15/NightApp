import Foundation
import SwiftData

extension NightLoopSchemaV4 {
@Model final class NightRoutineStep {
    @Attribute(.unique) var id: UUID
    var title: String
    var order: Int
    var routine: Routine?

    @Relationship(deleteRule: .cascade, inverse: \NightRoutineStepCompletion.step)
    var completions: [NightRoutineStepCompletion]

    init(
        id: UUID = UUID(),
        title: String,
        order: Int,
        routine: Routine
    ) {
        self.id = id
        self.title = title
        self.order = order
        self.routine = routine
        self.completions = []
    }
}
}

typealias NightRoutineStep = NightLoopSchemaV4.NightRoutineStep
