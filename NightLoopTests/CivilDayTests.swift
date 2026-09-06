import Foundation
import Testing
@testable import NightLoop

struct CivilDayTests {
    @Test func civilDayUsesTheProvidedTimeZone() {
        var bogota = Calendar(identifier: .gregorian)
        bogota.timeZone = TimeZone(identifier: "America/Bogota")!
        let date = Date(timeIntervalSince1970: 1_788_236_400)

        #expect(CivilDay(date: date, calendar: bogota).key == "2026-08-31")
    }

    @Test func tomorrowRangeSurvivesDaylightSavingTransition() throws {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        let components = DateComponents(year: 2026, month: 3, day: 7, hour: 20)
        let date = try #require(newYork.date(from: components))
        let range = try #require(newYork.tomorrowRange(relativeTo: date))

        #expect(range.upperBound.timeIntervalSince(range.lowerBound) == 23 * 60 * 60)
    }
}
