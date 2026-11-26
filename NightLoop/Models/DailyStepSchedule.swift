import Foundation
import SwiftData

struct DailyStepScheduleDraft: Equatable {
    var linkedCategory: RotatingCardCategory? = nil
    var weekdaysMask = RoutineSchedule.allDaysMask
    var variations = Array(repeating: "", count: 7)
}

extension NightLoopSchemaV8 {
    @Model final class DailyStepSchedule {
        @Attribute(.unique) var stepID: UUID
        var weekdaysMask: Int
        var variations: [String]

        init(stepID: UUID, draft: DailyStepScheduleDraft) {
            self.stepID = stepID
            self.weekdaysMask = draft.weekdaysMask
            self.variations = draft.variations
        }
    }
}

typealias DailyStepSchedule = NightLoopSchemaV8.DailyStepSchedule

extension DailyStepSchedule {
    static func draft(for stepID: UUID, in schedules: [DailyStepSchedule]) -> DailyStepScheduleDraft {
        guard let schedule = schedules.first(where: { $0.stepID == stepID }) else { return DailyStepScheduleDraft() }
        return DailyStepScheduleDraft(weekdaysMask: schedule.weekdaysMask, variations: schedule.variations)
    }

    static func includes(_ stepID: UUID, on date: Date, in schedules: [DailyStepSchedule], calendar: Calendar = .autoupdatingCurrent) -> Bool {
        RoutineSchedule.includes(date: date, mask: draft(for: stepID, in: schedules).weekdaysMask, calendar: calendar)
    }

    static func variation(for stepID: UUID, on date: Date, in schedules: [DailyStepSchedule], calendar: Calendar = .autoupdatingCurrent) -> String? {
        let values = draft(for: stepID, in: schedules).variations
        guard let weekday = RoutineWeekday(calendarWeekday: calendar.component(.weekday, from: date)),
              values.indices.contains(weekday.rawValue) else { return nil }
        let text = values[weekday.rawValue].trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
