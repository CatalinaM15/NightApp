import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openSettings) private var openSettings
    @AppStorage("floatsAboveOtherWindows") private var floatsAboveOtherWindows = true
    @AppStorage("joinsAllSpaces") private var joinsAllSpaces = false
    @AppStorage("nightlyReminderEnabled") private var reminderEnabled = false
    @AppStorage("nightlyReminderHour") private var reminderHour = 21
    @AppStorage("nightlyReminderMinute") private var reminderMinute = 0
    @StateObject private var dayCoordinator = JournalDayCoordinator()
    @StateObject private var undoCoordinator = CompletionUndoCoordinator()
    @State private var showsRoutineManager = false
    @State private var showsNewRoutine = false
    @Query private var routines: [Routine]

    private var activeRoutineCount: Int { routines.filter(\.isActive).count }

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
                JournalSection(title: "Today's Cards", systemImage: "sparkles") {
                    RoutineListView(
                        date: dayCoordinator.visibleDate,
                        undoCoordinator: undoCoordinator
                    )
                } accessory: {
                    HStack(spacing: 6) {
                        Button {
                            showsRoutineManager = true
                        } label: {
                            Label("Manage Routines", systemImage: "slider.horizontal.3")
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(JournalIconButtonStyle())
                        .help("Manage routines")

                        Button {
                            showsNewRoutine = true
                        } label: {
                            Label("New Routine", systemImage: "plus")
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(JournalIconButtonStyle())
                        .help(activeRoutineCount >= 7 ? "Seven active routines is the maximum" : "New routine")
                        .disabled(activeRoutineCount >= 7)
                    }
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
        .background(WindowConfigurator(
            floatsAboveOtherWindows: floatsAboveOtherWindows,
            joinsAllSpaces: joinsAllSpaces
        ))
        .overlay(alignment: .bottom) {
            if let message = undoCoordinator.message {
                UndoToast(message: message, undo: undoCoordinator.undo)
                    .padding()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: undoCoordinator.message)
        .tint(JournalPalette.ember)
        .sheet(isPresented: $showsRoutineManager) {
            RoutineManagerView(date: dayCoordinator.visibleDate)
        }
        .sheet(isPresented: $showsNewRoutine) {
            RoutineEditorView(title: "New Routine") { title, icon, weekdays, isGrouped, steps in
                try RoutineStore.create(
                    title: title,
                    iconName: icon,
                    scheduledWeekdaysMask: weekdays,
                    isGrouped: isGrouped,
                    steps: steps,
                    on: dayCoordinator.visibleDate,
                    in: modelContext
                )
            }
        }
        .task(id: reminderSyncID) {
            await NightlyReminderScheduler.shared.synchronize(
                isEnabled: reminderEnabled,
                time: NightlyReminderTime(hour: reminderHour, minute: reminderMinute)
            )
        }
        .toolbar {
            ToolbarItem {
                Toggle(isOn: $floatsAboveOtherWindows) {
                    Label("Keep on Top", systemImage: floatsAboveOtherWindows ? "pin.fill" : "pin")
                }
                .toggleStyle(.button)
                .help("Keep NightLoop above other windows")
                .accessibilityIdentifier("keep-on-top-toggle")
            }
            ToolbarItem {
                Button {
                    openSettings()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Open NightLoop settings")
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

    private var reminderSyncID: String {
        "\(reminderEnabled)-\(reminderHour)-\(reminderMinute)"
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

private struct JournalSection<Content: View, Accessory: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content
    @ViewBuilder let accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Label(title, systemImage: systemImage)
                    .font(JournalTypography.sectionTitle)
                    .foregroundStyle(JournalPalette.paperInk)
                Spacer()
                accessory
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .foregroundStyle(JournalPalette.paperInk)
        .journalCard()
    }
}

private extension JournalSection where Accessory == EmptyView {
    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
        self.accessory = EmptyView()
    }
}
