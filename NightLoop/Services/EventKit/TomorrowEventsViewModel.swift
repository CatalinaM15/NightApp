import AppKit
import EventKit
import Foundation

@MainActor
final class TomorrowEventsViewModel: ObservableObject {
    @Published private(set) var permissionState: CalendarPermissionState
    @Published private(set) var events: [NightLoopCalendarEvent] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let permissionManager: CalendarPermissionManager
    private let syncService: CalendarSyncService

    init(eventStore: EKEventStore = EKEventStore()) {
        let permissionManager = CalendarPermissionManager(eventStore: eventStore)
        self.permissionManager = permissionManager
        self.syncService = CalendarSyncService(eventStore: eventStore)
        self.permissionState = permissionManager.state
    }

    func refresh(for date: Date) async {
        permissionState = permissionManager.state
        guard permissionState == .fullAccess else {
            events = []
            errorMessage = nil
            return
        }

        isLoading = true
        defer { isLoading = false }
        do {
            events = try syncService.fetchEvents(on: date)
            errorMessage = nil
        } catch {
            events = []
            errorMessage = error.localizedDescription
        }
    }

    func requestAccess(for date: Date) async {
        isLoading = true
        defer { isLoading = false }
        do {
            _ = try await permissionManager.requestFullAccess()
            permissionState = permissionManager.state
            await refresh(for: date)
        } catch {
            permissionState = permissionManager.state
            errorMessage = error.localizedDescription
        }
    }

    func openCalendarPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else { return }
        NSWorkspace.shared.open(url)
    }
}
