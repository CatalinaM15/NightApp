import Foundation
import SwiftData

extension NightLoopSchemaV9 {
    @Model final class DailyStepActivityLink {
        @Attribute(.unique) var stepID: UUID
        var category: String?

        init(stepID: UUID, category: RotatingCardCategory?) {
            self.stepID = stepID
            self.category = category?.rawValue
        }
    }
}

typealias DailyStepActivityLink = NightLoopSchemaV9.DailyStepActivityLink

extension DailyStepActivityLink {
    static func category(for step: NightRoutineStep, in links: [DailyStepActivityLink]) -> RotatingCardCategory? {
        if let link = links.first(where: { $0.stepID == step.id }) {
            return link.category.flatMap(RotatingCardCategory.init(rawValue:))
        }
        // Existing Exercise and Body Care steps work without rebuilding the checklist.
        let title = step.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return [RotatingCardCategory.exercise, .bodyCare].first {
            title.compare($0.title, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }
}
