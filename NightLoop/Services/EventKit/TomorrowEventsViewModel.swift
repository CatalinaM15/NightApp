import AppKit
import EventKit
import Foundation

@MainActor
final class TomorrowEventsViewModel: ObservableObject {
    @Published private(set) var permissionState: CalendarPermissionState
    @Published private(set) var calendars: [EKCalendar] = []
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

    func refresh(for date: Date, selection: CalendarSelection = CalendarSelection(), entireWeek: Bool = false) async {
        permissionState = permissionManager.state
        guard permissionState == .fullAccess else {
            events = []
            calendars = []
            errorMessage = nil
            return
        }

        isLoading = true
        defer { isLoading = false }
        do {
            calendars = syncService.availableCalendars()
            events = try syncService.fetchEvents(on: date, selection: selection, entireWeek: entireWeek)
            errorMessage = nil
        } catch {
            events = []
            errorMessage = error.localizedDescription
        }
    }

    func requestAccess(for date: Date, selection: CalendarSelection = CalendarSelection(), entireWeek: Bool = false) async {
        isLoading = true
        defer { isLoading = false }
        do {
            _ = try await permissionManager.requestFullAccess()
            permissionState = permissionManager.state
            await refresh(for: date, selection: selection, entireWeek: entireWeek)
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
