import Foundation
import Testing
@testable import NightLoop

@Suite("Nightly reminder configuration")
struct NightlyReminderTests {
    @Test func producesARepeatingCalendarTimeWithoutADate() {
        let time = NightlyReminderTime(hour: 21, minute: 30)

        #expect(time.dateComponents.hour == 21)
        #expect(time.dateComponents.minute == 30)
        #expect(time.dateComponents.day == nil)
        #expect(time.dateComponents.timeZone == nil)
    }

    @Test func clampsCorruptedStoredValuesToAValidClockTime() {
        #expect(NightlyReminderTime(hour: -4, minute: -1) == NightlyReminderTime(hour: 0, minute: 0))
        #expect(NightlyReminderTime(hour: 99, minute: 90) == NightlyReminderTime(hour: 23, minute: 59))
    }
}
