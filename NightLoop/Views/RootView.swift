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
    @State private var planningTomorrow = false
    @State private var showsExperimentHistory = false
    @State private var showsWeeklyStats = false
    @State private var noteClearRevision = 0
    @State private var selectedNoteHasText = false

    private var planningDate: Date {
        planningTomorrow
            ? Calendar.autoupdatingCurrent.date(byAdding: .day, value: 1, to: dayCoordinator.visibleDate) ?? dayCoordinator.visibleDate
            : dayCoordinator.visibleDate
    }

    var body: some View {
        ZStack {
            if showsWeeklyStats {
                WeeklyStatsReviewView(date: dayCoordinator.visibleDate) {
                    showsWeeklyStats = false
                }
                .transition(reviewTransition)
            } else {
                journal
                    .transition(reviewTransition)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.48), value: showsWeeklyStats)
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
        .tint(JournalPalette.raised)
        .sheet(isPresented: $showsExperimentHistory) {
            ExperimentHistoryView()
        }
        .task(id: reminderSyncID) {
            await NightlyReminderScheduler.shared.synchronize(
                isEnabled: reminderEnabled,
                time: NightlyReminderTime(hour: reminderHour, minute: reminderMinute)
            )
        }
        .task(id: CivilDay(date: dayCoordinator.visibleDate).key) {
            try? DailyNoteStore.pruneNotes(before: dayCoordinator.visibleDate, in: modelContext)
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

    private var journal: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                WeeklyGlanceStrip(referenceDate: planningDate)
                JournalSection(
                    title: planningTomorrow ? "Tomorrow" : "Today",
                    systemImage: "calendar",
                    titleAction: { planningTomorrow.toggle() }
                ) {
                    GeometryReader { geometry in
                        let availableWidth = max(geometry.size.width - 13, 0)
                        HStack(alignment: .top, spacing: 12) {
                            ScrollView {
                                TomorrowEventsSection(
                                    date: planningDate,
                                    refreshRevision: dayCoordinator.calendarRefreshRevision
                                )
                            }
                            .frame(width: availableWidth * 0.6)
                            Divider()
                            DailyNoteView(
                                date: planningDate,
                                clearRevision: noteClearRevision,
                                hasText: $selectedNoteHasText,
                                undoCoordinator: undoCoordinator
                            )
                                .frame(width: availableWidth * 0.4)
                        }
                    }
                    .frame(height: 250)
                } accessory: {
                    HStack(spacing: 8) {
                        Label("Note", systemImage: "note.text")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(JournalPalette.paperInk)
                        Button("Clear") { noteClearRevision += 1 }
                            .buttonStyle(.borderless)
                            .disabled(!selectedNoteHasText)
                    }
                }
                JournalSection(title: "Today's Cards", systemImage: "sparkles") {
                    RoutineListView(
                        date: dayCoordinator.visibleDate,
                        planningTomorrow: $planningTomorrow
                    )
                } accessory: {
                    HStack(spacing: 6) {
                        Button {
                            showsExperimentHistory = true
                        } label: {
                            Label("Experiment History", systemImage: "archivebox")
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(JournalIconButtonStyle())
                        .help("Experiment history")
                    }
                }
                JournalSection(title: "Projects", systemImage: "checklist") {
                    ProjectPickerView(undoCoordinator: undoCoordinator)
                }
            }
            .padding(24)
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
                HStack(spacing: 10) {
                    Text("NightLoop")
                        .font(JournalTypography.journalTitle)
                    Button {
                        showsWeeklyStats = true
                    } label: {
                        Label("Weekly Stats", systemImage: "chart.bar.xaxis")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(JournalPalette.raised)
                    .padding(5)
                    .background(JournalPalette.card, in: Circle())
                    .frame(minWidth: 28, minHeight: 28)
                    .help("Open weekly stats")
                }
                Text(dayCoordinator.visibleDate.formatted(date: .complete, time: .omitted))
                    .font(JournalTypography.date)
                    .foregroundStyle(JournalPalette.secondaryInk)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var reviewTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .modifier(
                active: JournalPageFlip(angle: -92, opacity: 0),
                identity: JournalPageFlip(angle: 0, opacity: 1)
            )
    }

    private var reminderSyncID: String {
        "\(reminderEnabled)-\(reminderHour)-\(reminderMinute)"
    }
}

private struct JournalPageFlip: ViewModifier {
    let angle: Double
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.62)
            .opacity(opacity)
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
                .buttonStyle(.plain)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .foregroundStyle(JournalPalette.raised)
        .background(JournalPalette.cardOpaque, in: Capsule())
        .overlay { Capsule().stroke(JournalPalette.raised, lineWidth: 1) }
        .shadow(color: .black.opacity(0.24), radius: 8, y: 3)
        .accessibilityElement(children: .contain)
    }
}

private struct JournalSection<Content: View, Accessory: View>: View {
    let title: String
    let systemImage: String
    let titleAction: (() -> Void)?
    @ViewBuilder let content: Content
    @ViewBuilder let accessory: Accessory

    init(
        title: String,
        systemImage: String,
        titleAction: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.systemImage = systemImage
        self.titleAction = titleAction
        self.content = content()
        self.accessory = accessory()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                if let titleAction {
                    Button(action: titleAction) {
                        Label(title, systemImage: systemImage)
                            .font(JournalTypography.sectionTitle)
                            .foregroundStyle(JournalPalette.paperInk)
                    }
                    .buttonStyle(.plain)
                    .help("Show \(title == "Today" ? "tomorrow" : "today")")
                    .accessibilityHint("Switches the calendar, note, and rotating cards")
                } else {
                    Label(title, systemImage: systemImage)
                        .font(JournalTypography.sectionTitle)
                        .foregroundStyle(JournalPalette.paperInk)
                }
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
        self.titleAction = nil
        self.content = content()
        self.accessory = EmptyView()
    }
}
