import AppKit
import EventKit
import SwiftUI

struct TomorrowEventsSection: View {
    let date: Date
    let refreshRevision: Int
    let entireWeek: Bool
    let titleAction: (() -> Void)?
    let didConnect: () -> Void
    @AppStorage private var storedSelection: String
    @State private var showsCalendars = false
    @StateObject private var viewModel = TomorrowEventsViewModel()

    init(date: Date, refreshRevision: Int, entireWeek: Bool = false, titleAction: (() -> Void)? = nil, didConnect: @escaping () -> Void = {}) {
        self.date = date
        self.refreshRevision = refreshRevision
        self.entireWeek = entireWeek
        self.titleAction = titleAction
        self.didConnect = didConnect
        _storedSelection = AppStorage(wrappedValue: "", entireWeek ? "weekCalendarSelection" : "todayCalendarSelection")
    }

    private var selection: CalendarSelection { CalendarSelection(storedValue: storedSelection) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 2) {
                if let titleAction {
                    Button(action: titleAction) { sectionTitle }
                        .buttonStyle(.plain)
                        .help(Calendar.autoupdatingCurrent.isDateInToday(date) ? "Show tomorrow" : "Show today")
                } else {
                    sectionTitle
                }
                Spacer(minLength: 0)
                if viewModel.permissionState == .fullAccess {
                    Button("Choose Calendars", systemImage: "line.3.horizontal.decrease.circle") { showsCalendars = true }
                        .labelStyle(.iconOnly)
                        .buttonStyle(JournalIconButtonStyle())
                        .help(entireWeek ? "Choose calendars for Week" : "Choose calendars for Today and Tomorrow")
                        .popover(isPresented: $showsCalendars) {
                            CalendarSelectionView(calendars: viewModel.calendars, selection: Binding(
                                get: { selection },
                                set: { storedSelection = $0.storedValue }
                            ))
                        }
                }
                Button("Refresh Calendar", systemImage: "arrow.clockwise") { Task { await refresh() } }
                    .labelStyle(.iconOnly)
                    .buttonStyle(JournalIconButtonStyle())
                    .help("Refresh calendar")
                    .disabled(viewModel.isLoading)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) { content }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .task(id: "\(CivilDay(date: date).key)-\(refreshRevision)-\(storedSelection)") { await refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in Task { await refresh() } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in Task { await refresh() } }
    }

    private var sectionTitle: some View {
        Text(entireWeek ? "Week" : (Calendar.autoupdatingCurrent.isDateInToday(date) ? "Today" : "Tomorrow"))
            .font(JournalTypography.sectionTitle)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .layoutPriority(1)
    }

    @ViewBuilder private var content: some View {
        if let error = viewModel.errorMessage {
            Text(error).font(.caption).foregroundStyle(JournalPalette.paperSecondaryInk)
        }
        switch viewModel.permissionState {
        case .notDetermined:
            if entireWeek {
                Text("Connect Calendar on the left to see this week.").foregroundStyle(JournalPalette.paperSecondaryInk)
            } else {
                Text("Connect Calendar for Today and Week.").foregroundStyle(JournalPalette.paperSecondaryInk)
                Button("Connect Calendar") {
                    Task {
                        await viewModel.requestAccess(for: date, selection: selection, entireWeek: entireWeek)
                        if viewModel.permissionState == .fullAccess { didConnect() }
                    }
                }
                .disabled(viewModel.isLoading)
            }
        case .fullAccess:
            eventContent
        case .denied, .restricted, .writeOnly, .unknown:
            Text("Calendar access is unavailable.").foregroundStyle(JournalPalette.paperSecondaryInk)
            if !entireWeek && viewModel.permissionState != .restricted {
                Button("Open Calendar Privacy Settings") { viewModel.openCalendarPrivacySettings() }
            }
        }
    }

    @ViewBuilder private var eventContent: some View {
        let available = viewModel.calendars.map(\.calendarIdentifier)
        if !selection.includesAll && selection.identifiers.isEmpty {
            Text("No calendars selected. Choose calendars above.").foregroundStyle(JournalPalette.paperSecondaryInk)
        } else if !selection.includesAll && !selection.identifiers.isSubset(of: Set(available)) {
            Text("Some selected calendars are unavailable. Review your calendar selection.")
                .font(.caption).foregroundStyle(JournalPalette.paperSecondaryInk)
        }
        if viewModel.isLoading && viewModel.events.isEmpty {
            ProgressView("Reading calendar…")
        } else if viewModel.events.isEmpty && viewModel.errorMessage == nil {
            if selection.includesAll || !selection.resolvedIdentifiers(available: available).isEmpty {
                Text(entireWeek ? "No events this week in these calendars." : "No events for this day in these calendars.")
                    .foregroundStyle(JournalPalette.paperSecondaryInk)
            }
        } else if entireWeek {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(weekDays, id: \.self) { day in
                        let range = Calendar.autoupdatingCurrent.dayRange(containing: day)
                        let events = viewModel.events.filter { event in range.map { event.overlaps($0) } ?? false }
                        if !events.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                                    .font(.caption.weight(.semibold))
                                ForEach(events) { event in CalendarEventRow(event: event, dayRange: range) }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
                VStack(spacing: 0) {
                    ForEach(viewModel.events) { event in
                        CalendarEventRow(event: event, dayRange: Calendar.autoupdatingCurrent.dayRange(containing: date))
                        if event.id != viewModel.events.last?.id { Divider() }
                    }
                }
        }
    }

    private var weekDays: [Date] {
        let calendar = Calendar.autoupdatingCurrent
        guard let start = calendar.weekRange(containing: date)?.lowerBound else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private func refresh() async {
        await viewModel.refresh(for: date, selection: selection, entireWeek: entireWeek)
    }
}

private struct CalendarSelectionView: View {
    let calendars: [EKCalendar]
    @Binding var selection: CalendarSelection

    private var sources: [String] { Array(Set(calendars.map { $0.source.sourceIdentifier })).sorted() }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Calendars").font(.headline)
            Toggle("All calendars", isOn: Binding(
                get: { selection.includesAll },
                set: { selection = CalendarSelection(includesAll: $0) }
            ))
            Text("All includes calendars added later.").font(.caption).foregroundStyle(.secondary)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(sources, id: \.self) { source in
                        let items = calendars.filter { $0.source.sourceIdentifier == source }
                        VStack(alignment: .leading, spacing: 8) {
                            Text(items.first?.source.title ?? "Account").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            ForEach(items, id: \.calendarIdentifier) { calendar in
                                Toggle(isOn: Binding(
                                    get: { selection.contains(calendar.calendarIdentifier) },
                                    set: { _ in selection.toggle(calendar.calendarIdentifier, available: calendars.map(\.calendarIdentifier)) }
                                )) {
                                    HStack {
                                        Circle().fill(Color(nsColor: NSColor(cgColor: calendar.cgColor) ?? .gray)).frame(width: 8, height: 8)
                                        Text(calendar.title)
                                    }
                                }
                                .toggleStyle(.checkbox)
                            }
                        }
                    }
                    if calendars.isEmpty { Text("No calendars available.").foregroundStyle(.secondary) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 300)
        }
        .padding(16)
        .frame(width: 290)
        .foregroundStyle(Color.primary)
        .background(.background)
    }
}

private struct CalendarEventRow: View {
    let event: NightLoopCalendarEvent
    let dayRange: Range<Date>?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color(
                    red: event.calendarColor.red,
                    green: event.calendarColor.green,
                    blue: event.calendarColor.blue,
                    opacity: event.calendarColor.alpha
                ))
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .lineLimit(2)
                Text(timingLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(event.calendarTitle)
                    .font(.caption2)
                    .foregroundStyle(JournalPalette.paperSecondaryInk.opacity(0.82))
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }

    private var timingLabel: String {
        if event.isAllDay { return "All day" }
        guard let dayRange else { return event.startDate.formatted(date: .omitted, time: .shortened) }
        let startsBefore = event.startDate < dayRange.lowerBound
        let endsAfter = event.endDate > dayRange.upperBound
        if startsBefore && endsAfter { return "Continues through the day" }
        if startsBefore { return "Until \(event.endDate.formatted(date: .omitted, time: .shortened))" }
        if endsAfter { return "From \(event.startDate.formatted(date: .omitted, time: .shortened)) · continues" }
        return "\(event.startDate.formatted(date: .omitted, time: .shortened))–\(event.endDate.formatted(date: .omitted, time: .shortened))"
    }
}
