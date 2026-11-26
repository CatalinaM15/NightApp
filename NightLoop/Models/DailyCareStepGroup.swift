import Foundation
import SwiftData

enum DailyCarePeriod: String, CaseIterable, Identifiable {
    case morning, afternoon, night

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

// Keep grouping separate so existing routine schemas and completion identities stay intact.
extension NightLoopSchemaV6 {
    @Model final class DailyCareStepGroup {
        @Attribute(.unique) var stepID: UUID
        var period: String

        init(stepID: UUID, period: DailyCarePeriod) {
            self.stepID = stepID
            self.period = period.rawValue
        }
    }
}

typealias DailyCareStepGroup = NightLoopSchemaV6.DailyCareStepGroup

extension DailyCareStepGroup {
    static func period(for stepID: UUID, in groups: [DailyCareStepGroup]) -> DailyCarePeriod {
        groups.first { $0.stepID == stepID }.flatMap { DailyCarePeriod(rawValue: $0.period) } ?? .night
    }
}
