import Foundation
import SwiftData

extension NightLoopSchemaV5 {
@Model final class DailyNote {
    @Attribute(.unique) var date: Date
    var text: String

    init(
        date: Date,
        text: String = "",
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.date = calendar.startOfDay(for: date)
        self.text = text
    }
}
}

typealias DailyNote = NightLoopSchemaV5.DailyNote
