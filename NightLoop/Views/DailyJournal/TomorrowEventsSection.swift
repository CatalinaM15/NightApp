import SwiftUI

struct TomorrowEventsSection: View {
    let referenceDate: Date
    let refreshRevision: Int

    @StateObject private var viewModel = TomorrowEventsViewModel()

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.events.isEmpty {
                ProgressView("Reading tomorrow's calendar…")
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                content
            }
        }
        .task(id: refreshID) {
            await viewModel.refresh(relativeTo: referenceDate)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.permissionState {
        case .notDetermined:
            permissionPrompt
        case .fullAccess:
            eventContent
        case .denied, .restricted, .writeOnly:
            unavailablePrompt
        case .unknown:
            Text("Calendar access is temporarily unavailable.")
                .foregroundStyle(.secondary)
        }
    }

    private var permissionPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("See tomorrow's events beside your evening plan. NightLoop only reads them on this Mac.")
                .foregroundStyle(.secondary)
            Button("Connect Calendar") {
                Task { await viewModel.requestAccess(relativeTo: referenceDate) }
            }
        }
    }

    private var unavailablePrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(viewModel.permissionState == .writeOnly
                 ? "NightLoop needs full calendar access to read tomorrow's events."
                 : "Calendar access is off. Your routines and projects still work normally.")
                .foregroundStyle(.secondary)
            if viewModel.permissionState != .restricted {
                Button("Open Privacy Settings") { viewModel.openCalendarPrivacySettings() }
            }
        }
    }

    @ViewBuilder
    private var eventContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).foregroundStyle(.secondary)
            } else if viewModel.events.isEmpty {
                ContentUnavailableView(
                    "Tomorrow Is Clear",
                    systemImage: "calendar.badge.checkmark",
                    description: Text("No active calendar events are scheduled.")
                )
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 0) {
                    ForEach(viewModel.events) { event in
                        CalendarEventRow(event: event, tomorrowRange: tomorrowRange)
                        if event.id != viewModel.events.last?.id { Divider().padding(.leading, 18) }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await viewModel.refresh(relativeTo: referenceDate) }
                }
                .labelStyle(.iconOnly)
                .help("Refresh calendar")
                .disabled(viewModel.isLoading)
            }
        }
    }

    private var tomorrowRange: Range<Date>? {
        Calendar.autoupdatingCurrent.tomorrowRange(relativeTo: referenceDate)
    }

    private var refreshID: String {
        "\(CivilDay(date: referenceDate).key)-\(refreshRevision)"
    }
}

private struct CalendarEventRow: View {
    let event: NightLoopCalendarEvent
    let tomorrowRange: Range<Date>?

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
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }

    private var timingLabel: String {
        if event.isAllDay { return "All day" }
        guard let tomorrowRange else { return event.startDate.formatted(date: .omitted, time: .shortened) }
        let startsBefore = event.startDate < tomorrowRange.lowerBound
        let endsAfter = event.endDate > tomorrowRange.upperBound
        if startsBefore && endsAfter { return "Continues through tomorrow" }
        if startsBefore { return "Until \(event.endDate.formatted(date: .omitted, time: .shortened))" }
        if endsAfter { return "From \(event.startDate.formatted(date: .omitted, time: .shortened)) · continues" }
        return "\(event.startDate.formatted(date: .omitted, time: .shortened))–\(event.endDate.formatted(date: .omitted, time: .shortened))"
    }
}
