import SwiftUI

struct RootView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("floatsAboveOtherWindows") private var floatsAboveOtherWindows = true
    @StateObject private var dayCoordinator = JournalDayCoordinator()
    @StateObject private var undoCoordinator = CompletionUndoCoordinator()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                WeeklyGlanceStrip(referenceDate: dayCoordinator.visibleDate)
                JournalSection(title: "Tomorrow", systemImage: "calendar") {
                    TomorrowEventsSection(
                        referenceDate: dayCoordinator.visibleDate,
                        refreshRevision: dayCoordinator.calendarRefreshRevision
                    )
                }
                JournalSection(title: "Evening Ritual", systemImage: "moon.stars") {
                    RoutineListView(
                        date: dayCoordinator.visibleDate,
                        undoCoordinator: undoCoordinator
                    )
                }
                JournalSection(title: "Projects", systemImage: "checklist") {
                    ProjectPickerView(undoCoordinator: undoCoordinator)
                }
            }
            .padding(24)
        }
        .frame(minWidth: 380, minHeight: 520)
        .foregroundStyle(JournalPalette.ink)
        .background { LeatherJournalBackground() }
        .background(WindowConfigurator(floatsAboveOtherWindows: floatsAboveOtherWindows))
        .overlay(alignment: .bottom) {
            if let message = undoCoordinator.message {
                UndoToast(message: message, undo: undoCoordinator.undo)
                    .padding()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: undoCoordinator.message)
        .tint(JournalPalette.ember)
        .toolbar {
            ToolbarItem {
                Toggle(isOn: $floatsAboveOtherWindows) {
                    Label("Keep on Top", systemImage: floatsAboveOtherWindows ? "pin.fill" : "pin")
                }
                .toggleStyle(.button)
                .help("Keep NightLoop above other windows")
                .accessibilityIdentifier("keep-on-top-toggle")
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(JournalPalette.ember)
                .frame(width: 42, height: 42)
                .background(JournalPalette.raised.opacity(0.72), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("TONIGHT'S JOURNAL")
                    .font(JournalTypography.eyebrow)
                    .tracking(1.4)
                    .foregroundStyle(JournalPalette.ember)
                Text("NightLoop")
                    .font(JournalTypography.journalTitle)
                Text(dayCoordinator.visibleDate.formatted(date: .complete, time: .omitted))
                    .font(JournalTypography.date)
                    .foregroundStyle(JournalPalette.secondaryInk)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct UndoToast: View {
    let message: String
    let undo: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Text(message)
                .lineLimit(1)
            Button("Undo", action: undo)
                .keyboardShortcut("z", modifiers: .command)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .foregroundStyle(JournalPalette.ink)
        .background(JournalPalette.raised, in: Capsule())
        .overlay { Capsule().stroke(JournalPalette.ember.opacity(0.5), lineWidth: 0.75) }
        .shadow(color: .black.opacity(0.24), radius: 8, y: 3)
        .accessibilityElement(children: .contain)
    }
}

private struct JournalSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(JournalTypography.sectionTitle)
                .foregroundStyle(JournalPalette.paperInk)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .foregroundStyle(JournalPalette.paperInk)
        .journalCard()
    }
}
