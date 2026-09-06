import AppKit
import Combine
import Foundation

@MainActor
final class JournalDayCoordinator: ObservableObject {
    @Published private(set) var visibleDate: Date
    @Published private(set) var calendarRefreshRevision = 0

    private let calendar: Calendar
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    init(now: Date = .now, calendar: Calendar = .autoupdatingCurrent, observesSystem: Bool = true) {
        self.visibleDate = now
        self.calendar = calendar
        guard observesSystem else { return }

        observers.append(NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshCalendarForDayChange() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshAfterWake() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshIfDayChanged() }
        })
        scheduleMidnightRefresh()
    }

    deinit {
        timer?.invalidate()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
    }

    func refresh(at now: Date = .now) {
        if shouldRollOver(to: now) { visibleDate = now }
        scheduleMidnightRefresh()
    }

    private func refreshCalendarForDayChange() {
        refresh()
        calendarRefreshRevision += 1
    }

    private func refreshAfterWake() {
        refresh()
        calendarRefreshRevision += 1
    }

    private func refreshIfDayChanged() {
        guard shouldRollOver(to: .now) else { return }
        refreshCalendarForDayChange()
    }

    func shouldRollOver(to date: Date) -> Bool {
        !calendar.isDate(visibleDate, inSameDayAs: date)
    }

    private func scheduleMidnightRefresh() {
        timer?.invalidate()
        let start = calendar.startOfDay(for: .now)
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: start) else { return }
        timer = Timer(fire: nextDay, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.refreshCalendarForDayChange() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }
}
