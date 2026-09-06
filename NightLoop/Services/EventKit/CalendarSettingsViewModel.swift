import AppKit
import EventKit
import Foundation

@MainActor
final class CalendarSettingsViewModel: ObservableObject {
    @Published private(set) var permissionState: CalendarPermissionState
    @Published private(set) var isRequesting = false
    @Published var errorMessage: String?

    private let permissionManager: CalendarPermissionManager

    init(eventStore: EKEventStore = EKEventStore()) {
        let manager = CalendarPermissionManager(eventStore: eventStore)
        permissionManager = manager
        permissionState = manager.state
    }

    var statusDescription: String {
        switch permissionState {
        case .fullAccess: "Connected — tomorrow’s events can be read."
        case .notDetermined: "Not connected."
        case .denied: "Access is disabled in System Settings."
        case .restricted: "Calendar access is restricted on this Mac."
        case .writeOnly: "Full calendar access is required to read events."
        case .unknown: "Calendar permission is currently unavailable."
        }
    }

    func refresh() {
        permissionState = permissionManager.state
    }

    func connect() async {
        isRequesting = true
        defer { isRequesting = false }
        do {
            _ = try await permissionManager.requestFullAccess()
            permissionState = permissionManager.state
        } catch {
            permissionState = permissionManager.state
            errorMessage = error.localizedDescription
        }
    }

    func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else { return }
        NSWorkspace.shared.open(url)
    }
}
