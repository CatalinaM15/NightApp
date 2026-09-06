import Foundation
import UserNotifications

struct NightlyReminderTime: Equatable {
    let hour: Int
    let minute: Int

    init(hour: Int, minute: Int) {
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    var dateComponents: DateComponents {
        DateComponents(hour: hour, minute: minute)
    }
}

enum NightlyReminderError: LocalizedError {
    case permissionDenied

    var errorDescription: String? {
        "Notifications are disabled for NightLoop. You can enable them in System Settings."
    }
}

actor NightlyReminderScheduler {
    static let shared = NightlyReminderScheduler()
    static let identifier = "nightloop.nightly-ritual"

    private let center = UNUserNotificationCenter.current()

    func enable(at time: NightlyReminderTime) async throws {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            guard try await center.requestAuthorization(options: [.alert, .sound]) else {
                throw NightlyReminderError.permissionDenied
            }
        case .denied:
            throw NightlyReminderError.permissionDenied
        case .authorized, .provisional, .ephemeral:
            break
        @unknown default:
            throw NightlyReminderError.permissionDenied
        }

        try await schedule(at: time)
    }

    func synchronize(isEnabled: Bool, time: NightlyReminderTime) async {
        if isEnabled {
            try? await enable(at: time)
        } else {
            disable()
        }
    }

    func disable() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
        center.removeDeliveredNotifications(withIdentifiers: [Self.identifier])
    }

    private func schedule(at time: NightlyReminderTime) async throws {
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])

        let content = UNMutableNotificationContent()
        content.title = "A quiet moment for NightLoop"
        content.body = "Review tomorrow, close your loops, and settle the evening."
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: time.dateComponents,
            repeats: true
        )
        try await center.add(UNNotificationRequest(
            identifier: Self.identifier,
            content: content,
            trigger: trigger
        ))
    }
}
