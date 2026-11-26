import SwiftData
import SwiftUI

struct DailyCareView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var routines: [Routine]
    @Query private var groups: [DailyCareStepGroup]
    @Query private var schedules: [DailyStepSchedule]
    @Query private var activityLinks: [DailyStepActivityLink]
    @Query(sort: \CardOption.sortOrder) private var options: [CardOption]
    @Query private var history: [SlotSelectionHistory]
    @Query private var maintenance: [MaintenanceItem]
    let date: Date
    @ObservedObject var undoCoordinator: CompletionUndoCoordinator
    @State private var isExpanded = false
    @State private var showsEditor = false
    @State private var selectedCategory: RotatingCardCategory?
    @State private var selectedChore: MaintenanceItem?
    @State private var choreToUncheck: MaintenanceItem?
    @State private var errorMessage: String?

    private let linkedCategories: [RotatingCardCategory] = [.exercise, .bodyCare]
    private var routine: Routine? { TodayCardsStore.routine(forSlot: 4, in: routines) }
    private var orderedSteps: [NightRoutineStep] { routine?.steps.sorted { $0.order < $1.order } ?? [] }
    private var visibleSteps: [NightRoutineStep] {
        orderedSteps.filter { DailyStepSchedule.includes($0.id, on: date, in: schedules) }
    }
    private var unplacedCategories: [RotatingCardCategory] {
        linkedCategories.filter { category in
            !visibleSteps.contains { DailyStepActivityLink.category(for: $0, in: activityLinks) == category }
        }
    }
    private var chores: [MaintenanceItem] { MaintenanceStore.chores(on: date, among: maintenance) }
    private var completedCount: Int {
        visibleSteps.filter { stepIsComplete($0) }.count +
        unplacedCategories.filter { selection(for: $0)?.completedAt != nil }.count +
        chores.filter { $0.isRecordedThisWeek(on: date) }.count
    }
    private var resolutionID: String {
        "\(CivilDay(date: date).key)-\(options.map { "\($0.id):\($0.scheduledWeekdaysMask)" }.joined())"
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 16) {
                if let routine {
                    HStack {
                        Spacer()
                        Button("Edit Daily", systemImage: "pencil") { showsEditor = true }
                            .buttonStyle(.borderless)
                    }
                    ForEach(DailyCarePeriod.allCases) { period in
                        let steps = visibleSteps.filter { DailyCareStepGroup.period(for: $0.id, in: groups) == period }
                        if !steps.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(period.title).font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text("\(steps.filter { stepIsComplete($0) }.count)/\(steps.count)")
                                        .font(.caption).foregroundStyle(JournalPalette.paperSecondaryInk)
                                }
                                ForEach(steps) { step in stepRow(step, in: routine) }
                            }
                        }
                    }
                } else {
                    Button("Set Up Daily") {
                        do {
                            try TodayCardsStore.bootstrap(in: modelContext)
                            showsEditor = true
                        } catch { errorMessage = error.localizedDescription }
                    }
                }
                if !unplacedCategories.isEmpty || !chores.isEmpty {
                    Divider()
                    Text("For today").font(.subheadline.weight(.semibold))
                    ForEach(unplacedCategories) { category in activityRow(category) }
                    ForEach(chores) { chore in choreRow(chore) }
                }
            }
            .padding(.top, 12)
        } label: {
            HStack {
                Label("Daily", systemImage: "heart.text.square").font(JournalTypography.sectionTitle)
                Spacer()
                Text("\(completedCount) of \(visibleSteps.count + unplacedCategories.count + chores.count) complete")
                    .font(.caption).foregroundStyle(JournalPalette.paperSecondaryInk)
            }
            .contentShape(Rectangle())
        }
        .padding(16)
        .foregroundStyle(JournalPalette.paperInk)
        .journalCard()
        .task(id: resolutionID) {
            do {
                if let routine { try RoutineStore.ensureDailyExercise(routine, on: date, in: modelContext) }
                for category in linkedCategories {
                    _ = try TodayCardsStore.resolveSelection(category: category, on: date, options: options, history: history, in: modelContext)
                }
            } catch { errorMessage = error.localizedDescription }
        }
        .sheet(isPresented: $showsEditor) { editor }
        .sheet(item: $selectedChore) { chore in
            MaintenanceDetailView(item: chore, kind: .chores, undoCoordinator: undoCoordinator)
        }
        .popover(item: $selectedCategory, arrowEdge: .bottom) { category in
            RotatingCardPicker(category: category, date: date, options: options, history: history) { option in
                do {
                    _ = try TodayCardsStore.choose(option, category: category, on: date, history: history, in: modelContext)
                    undoCoordinator.clear()
                    selectedCategory = nil
                } catch { errorMessage = error.localizedDescription }
            }
            .foregroundStyle(Color.primary)
            .background(.background)
        }
        .confirmationDialog("Clear this week's completions?", isPresented: Binding(
            get: { choreToUncheck != nil }, set: { if !$0 { choreToUncheck = nil } }
        ), titleVisibility: .visible, presenting: choreToUncheck) { chore in
            Button("Clear This Week", role: .destructive) { setChoreCompletion(false, chore: chore) }
            Button("Cancel", role: .cancel) { choreToUncheck = nil }
        } message: { chore in
            Text("\(chore.title) has multiple dates recorded this week. Unchecking removes those dates; earlier history is kept.")
        }
        .alert("Daily Could Not Be Updated", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "Please try again.") }
    }

    @ViewBuilder private var editor: some View {
        if let routine {
            RoutineEditorView(
                title: "Edit Daily", initialTitle: "Daily", initialIcon: routine.iconName, initialIsGrouped: true,
                initialSteps: orderedSteps.map { step in
                    var schedule = DailyStepSchedule.draft(for: step.id, in: schedules)
                    schedule.linkedCategory = DailyStepActivityLink.category(for: step, in: activityLinks)
                    return RoutineStepDraft(id: step.id, title: step.title, carePeriod: DailyCareStepGroup.period(for: step.id, in: groups),
                                            dailySchedule: schedule)
                },
                allowsTypeSelection: false, allowsTitleEditing: false, showsSchedule: false, showsCarePeriods: true
            ) { _, icon, _, _, steps in
                try RoutineStore.update(routine, title: "Daily", iconName: icon, steps: steps, in: modelContext)
                undoCoordinator.clear()
            }
        }
    }

    private func stepIsComplete(_ step: NightRoutineStep) -> Bool {
        if let category = DailyStepActivityLink.category(for: step, in: activityLinks) {
            return selection(for: category)?.completedAt != nil
        }
        return RoutineGroupCompletionStore.isComplete(step, on: date)
    }

    @ViewBuilder private func stepRow(_ step: NightRoutineStep, in routine: Routine) -> some View {
        if let category = DailyStepActivityLink.category(for: step, in: activityLinks) {
            VStack(alignment: .leading, spacing: 3) {
                activityRow(category, title: step.title)
                if let variation = DailyStepSchedule.variation(for: step.id, on: date, in: schedules) {
                    Text(variation).font(.caption).foregroundStyle(JournalPalette.paperSecondaryInk)
                }
            }
        } else {
            let completed = stepIsComplete(step)
            Toggle(isOn: Binding(get: { completed }, set: { setCompletion($0, for: step, in: routine) })) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(step.title)
                    if let variation = DailyStepSchedule.variation(for: step.id, on: date, in: schedules) {
                        Text(variation).font(.caption)
                    }
                }
                .foregroundStyle(completed ? JournalPalette.paperSecondaryInk : JournalPalette.paperInk)
            }
            .toggleStyle(.checkbox)
        }
    }

    private func selection(for category: RotatingCardCategory) -> SlotSelectionHistory? {
        history.first { $0.category == category.rawValue && Calendar.autoupdatingCurrent.isDate($0.date, inSameDayAs: date) }
    }

    private func activityRow(_ category: RotatingCardCategory, title: String? = nil) -> some View {
        let selected = selection(for: category)
        return Toggle(isOn: Binding(
            get: { selected?.completedAt != nil },
            set: { completed in
                if let selected { setActivityCompletion(completed, selection: selected) }
                else { selectedCategory = category }
            }
        )) {
            HStack(spacing: 10) {
                Text(title ?? category.title).font(.body).frame(width: 100, alignment: .leading)
                Button(selected?.optionName ?? "Choose activity") { selectedCategory = category }
                    .buttonStyle(.borderless)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help("Choose or change \(category.title.lowercased())")
            }
        }
        .toggleStyle(.checkbox)
        .accessibilityLabel("\(title ?? category.title), \(selected?.optionName ?? "choose activity")")
    }

    private func choreRow(_ chore: MaintenanceItem) -> some View {
        HStack(spacing: 10) {
            Toggle("Complete \(chore.title)", isOn: Binding(
                get: { chore.isRecordedThisWeek(on: date) },
                set: { completed in
                    let range = Calendar.autoupdatingCurrent.weekRange(containing: date)
                    let count = chore.records.filter { record in range.map { $0.contains(record.date) } ?? false }.count
                    if !completed && count > 1 { choreToUncheck = chore }
                    else { setChoreCompletion(completed, chore: chore) }
                }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)
            Text("Chores").font(.body).frame(width: 100, alignment: .leading)
                .opacity(chore.id == chores.first?.id ? 1 : 0)
            Button(chore.title) { selectedChore = chore }
                .buttonStyle(.plain)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help("View chore details and history")
        }
    }

    private func setChoreCompletion(_ completed: Bool, chore: MaintenanceItem) {
        do {
            _ = try MaintenanceStore.setWeeklyCompletion(completed, for: chore, on: date, in: modelContext)
            choreToUncheck = nil
            undoCoordinator.clear()
        } catch { errorMessage = error.localizedDescription }
    }

    private func setActivityCompletion(_ completed: Bool, selection: SlotSelectionHistory) {
        do {
            if completed { try TodayCardsStore.complete(selection, in: modelContext) }
            else { try TodayCardsStore.undoCompletion(selection, in: modelContext) }
            undoCoordinator.clear()
        } catch { errorMessage = error.localizedDescription }
    }

    private func setCompletion(_ completed: Bool, for step: NightRoutineStep, in routine: Routine) {
        do {
            try updateCompletion(completed, for: step, in: routine, on: date)
            undoCoordinator.clear()
        } catch { errorMessage = error.localizedDescription }
    }

    private func updateCompletion(_ completed: Bool, for step: NightRoutineStep, in routine: Routine, on date: Date) throws {
        if completed { _ = try RoutineGroupCompletionStore.complete(step, in: routine, at: date, in: modelContext) }
        else { try RoutineGroupCompletionStore.uncomplete(step, in: routine, at: date, in: modelContext) }
    }
}
