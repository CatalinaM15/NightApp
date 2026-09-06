import Foundation

struct CivilDay: Hashable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init(date: Date, calendar: Calendar = .autoupdatingCurrent) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.year = components.year ?? 0
        self.month = components.month ?? 0
        self.day = components.day ?? 0
    }

    var key: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }
}

extension Calendar {
    func tomorrowRange(relativeTo date: Date) -> Range<Date>? {
        let today = startOfDay(for: date)
        guard let tomorrow = self.date(byAdding: .day, value: 1, to: today),
              let dayAfterTomorrow = self.date(byAdding: .day, value: 1, to: tomorrow) else {
            return nil
        }
        return tomorrow..<dayAfterTomorrow
    }
}
