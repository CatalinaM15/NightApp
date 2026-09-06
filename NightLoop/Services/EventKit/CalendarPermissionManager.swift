import EventKit
import Foundation

enum CalendarPermissionState: Equatable {
    case notDetermined
    case fullAccess
    case denied
    case restricted
    case writeOnly
    case unknown
}

@MainActor
final class CalendarPermissionManager {
    let eventStore: EKEventStore

    init(eventStore: EKEventStore) {
        self.eventStore = eventStore
    }

    var state: CalendarPermissionState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: .notDetermined
        case .fullAccess, .authorized: .fullAccess
        case .denied: .denied
        case .restricted: .restricted
        case .writeOnly: .writeOnly
        @unknown default: .unknown
        }
    }

    func requestFullAccess() async throws -> Bool {
        try await eventStore.requestFullAccessToEvents()
    }
}
