import SwiftData
import SwiftUI

struct RoutineListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Routine.cardSlot) private var routines: [Routine]
    @Query(sort: \CardOption.sortOrder) private var options: [CardOption]
    @Query(sort: \SlotSelectionHistory.date, order: .reverse) private var history: [SlotSelectionHistory]
    let date: Date
    @Binding var planningTomorrow: Bool
    @State private var selectedCategory: RotatingCardCategory?
    @State private var errorMessage: String?

    private var viewedDate: Date {
        planningTomorrow ? Calendar.autoupdatingCurrent.date(byAdding: .day, value: 1, to: date) ?? date : date
    }
    private var resolutionID: String {
        "\(CivilDay(date: viewedDate).key)-\(options.map { "\($0.id):\($0.scheduledWeekdaysMask)" }.joined())"
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(RotatingCardCategory.allCases) { category in
                RotatingCardTile(
                    category: category,
                    selection: selection(for: category),
                    canComplete: !planningTomorrow,
                    choose: { selectedCategory = category },
                    complete: { complete($0) }
                )
            }
            GroupedCardTile(slot: 4, fallbackTitle: "Daily Care", routine: TodayCardsStore.routine(forSlot: 4, in: routines), date: date, reportError: report)
            ForEach(5...7, id: \.self) { slot in
                GroupedCardTile(slot: slot, fallbackTitle: "Experiment \(slot - 4)", routine: TodayCardsStore.routine(forSlot: slot, in: routines), date: date, reportError: report)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(planningTomorrow ? "Tomorrow's cards" : "Today's cards")
        .task(id: resolutionID) { resolveDefaults() }
        .popover(item: $selectedCategory, arrowEdge: .bottom) { category in
            RotatingCardPicker(category: category, date: viewedDate, options: options, history: history) { option in
                perform {
                    _ = try TodayCardsStore.choose(option, category: category, on: viewedDate, history: history, in: modelContext)
                    selectedCategory = nil
                }
            }
        }
        .alert("Cards Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "The card could not be updated.") }
    }

    private func selection(for category: RotatingCardCategory) -> SlotSelectionHistory? {
        history.first { $0.category == category.rawValue && Calendar.autoupdatingCurrent.isDate($0.date, inSameDayAs: viewedDate) }
    }
    private func resolveDefaults() {
        for category in RotatingCardCategory.allCases {
            perform { _ = try TodayCardsStore.resolveSelection(category: category, on: viewedDate, options: options, history: history, in: modelContext) }
        }
    }
    private func complete(_ selection: SlotSelectionHistory) {
        perform {
            try TodayCardsStore.toggleCompletion(selection, in: modelContext)
        }
    }
    private func report(_ message: String) { errorMessage = message }
    private func perform(_ action: () throws -> Void) { do { try action() } catch { report(error.localizedDescription) } }
}

private struct RotatingCardTile: View {
    let category: RotatingCardCategory
    let selection: SlotSelectionHistory?
    let canComplete: Bool
    let choose: () -> Void
    let complete: (SlotSelectionHistory) -> Void

    var body: some View {
        CardTileSurface(
            title: selection?.optionName ?? "Set up",
            iconName: category.iconName,
            progress: selection?.completedAt == nil ? 0 : 1
        )
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .gesture(
            LongPressGesture(minimumDuration: 0.45)
                .exclusively(before: TapGesture())
                .onEnded { gesture in
                    switch gesture {
                    case .first:
                        choose()
                    case .second:
                        activate()
                    }
                }
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            activate()
        }
        .help(selection == nil ? "Choose \(category.title)" : "Tap to complete; hold to change")
        .accessibilityLabel("\(category.title), \(selection?.optionName ?? "not selected")")
    }

    private func activate() {
        guard let selection, canComplete else { choose(); return }
        complete(selection)
    }
}

private struct GroupedCardTile: View {
    @Environment(\.modelContext) private var modelContext
    let slot: Int
    let fallbackTitle: String
    let routine: Routine?
    let date: Date
    let reportError: (String) -> Void
    @State private var showsChecklist = false
    @State private var showsEditor = false
    @State private var confirmsArchive = false

    private var progress: Double {
        guard let routine, !routine.steps.isEmpty else { return 0 }
        return Double(RoutineGroupCompletionStore.completedStepCount(for: routine, on: date)) / Double(routine.steps.count)
    }

    var body: some View {
        Button {
            guard let routine else { showsEditor = true; return }
            if progress >= 1 {
                do { try RoutineGroupCompletionStore.uncompleteGroup(routine, at: date, in: modelContext) }
                catch { reportError(error.localizedDescription) }
            } else {
                showsChecklist = true
            }
        } label: {
            CardTileSurface(title: routine?.title ?? fallbackTitle, iconName: routine?.iconName ?? "plus", progress: progress, isEmpty: routine == nil)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showsChecklist, arrowEdge: .bottom) {
            if let routine {
                GroupedRoutineChecklist(
                    routine: routine, date: date,
                    edit: { showsChecklist = false; showsEditor = true },
                    archive: slot > 4 ? { showsChecklist = false; confirmsArchive = true } : nil,
                    reportError: reportError
                )
            }
        }
        .sheet(isPresented: $showsEditor) { editor }
        .confirmationDialog("Archive Experiment?", isPresented: $confirmsArchive, titleVisibility: .visible) {
            Button("Archive", role: .destructive) {
                guard let routine else { return }
                do { try TodayCardsStore.archiveExperiment(routine, on: date, in: modelContext) }
                catch { reportError(error.localizedDescription) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("A summary will be saved in history and this slot will become empty.") }
    }

    @ViewBuilder private var editor: some View {
        if let routine {
            RoutineEditorView(
                title: slot == 4 ? "Edit Daily Care" : "Edit Experiment",
                initialTitle: routine.title, initialIcon: routine.iconName,
                initialScheduledWeekdaysMask: RoutineSchedule.allDaysMask, initialIsGrouped: true,
                initialSteps: routine.steps.sorted { $0.order < $1.order }.map { RoutineStepDraft(id: $0.id, title: $0.title) },
                allowsTypeSelection: false, allowsTitleEditing: slot != 4, showsSchedule: false
            ) { title, icon, _, _, steps in
                try RoutineStore.update(routine, title: slot == 4 ? "Daily Care" : title, iconName: icon, scheduledWeekdaysMask: RoutineSchedule.allDaysMask, steps: steps, in: modelContext)
            }
        } else {
            RoutineEditorView(
                title: "New \(fallbackTitle)", initialIsGrouped: true,
                initialSteps: [RoutineStepDraft()], allowsTypeSelection: false, showsSchedule: false
            ) { title, icon, _, _, steps in
                try TodayCardsStore.createExperiment(number: slot - 4, title: title, iconName: icon, steps: steps, on: date, in: modelContext)
            }
        }
    }
}

private struct CardTileSurface: View {
    let title: String
    let iconName: String
    let progress: Double
    var isEmpty = false
    private var normalizedProgress: Double { min(max(progress, 0), 1) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(JournalPalette.card)
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(JournalPalette.raised.opacity(normalizedProgress))
            if isEmpty {
                RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(JournalPalette.paperRule.opacity(0.5), style: StrokeStyle(lineWidth: 0.7, dash: [3]))
            }
            VStack(spacing: 6) {
                Image(systemName: iconName).font(.body.weight(.medium))
                Text(title).font(.system(size: 9, weight: .semibold, design: .rounded)).lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 3)
            .foregroundStyle(normalizedProgress >= 0.55 ? JournalPalette.ink : JournalPalette.paperInk)
        }
        .frame(maxWidth: .infinity, minHeight: 76)
        .accessibilityValue("\(Int((normalizedProgress * 100).rounded())) percent complete")
    }
}

private struct RotatingCardPicker: View {
    @Environment(\.modelContext) private var modelContext
    let category: RotatingCardCategory
    let date: Date
    let options: [CardOption]
    let history: [SlotSelectionHistory]
    let choose: (CardOption) -> Void
    @State private var newOptionName = ""
    @State private var editingOption: CardOption?
    @State private var errorMessage: String?
    private var categoryOptions: [CardOption] { TodayCardsStore.options(for: category, in: options) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(category.title).font(.headline)
            Text(date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(categoryOptions) { option in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.name)
                                Text("\(lastPickedText(for: option))  •  \(scheduleText(for: option))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button("Choose") { choose(option) }
                                .buttonStyle(.borderless)
                            Button("Edit", systemImage: "pencil") { editingOption = option }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                                .help("Edit name and default days")
                        }
                        .padding(.vertical, 3)
                    }
                }
            }.frame(maxHeight: 310)
            HStack {
                TextField("New \(category.title.lowercased()) option", text: $newOptionName)
                Button("Add") {
                    perform {
                        try TodayCardsStore.addOption(
                            named: newOptionName,
                            category: category,
                            allOptions: options,
                            in: modelContext
                        )
                        newOptionName = ""
                    }
                }
                .disabled(newOptionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red) }
        }
        .padding(16).frame(width: 390)
        .sheet(item: $editingOption) { option in
            CardOptionEditor(option: option, allOptions: options, history: history)
        }
    }
    private func lastPickedText(for option: CardOption) -> String {
        guard let days = TodayCardsStore.daysSinceLastPicked(option: option, before: date, history: history) else { return "Never picked" }
        return days == 1 ? "1 day ago" : "\(days) days ago"
    }
    private func scheduleText(for option: CardOption) -> String {
        let days = RoutineWeekday.allCases.filter {
            RoutineSchedule.contains($0, in: option.scheduledWeekdaysMask)
        }
        return days.isEmpty ? "No default days" : days.map(\.shortName).joined(separator: ", ")
    }
    private func perform(_ action: () throws -> Void) { do { try action() } catch { errorMessage = error.localizedDescription } }
}

private struct CardOptionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let option: CardOption
    let allOptions: [CardOption]
    let history: [SlotSelectionHistory]
    @State private var name: String
    @State private var weekdaysMask: Int
    @State private var errorMessage: String?

    init(option: CardOption, allOptions: [CardOption], history: [SlotSelectionHistory]) {
        self.option = option
        self.allOptions = allOptions
        self.history = history
        _name = State(initialValue: option.name)
        _weekdaysMask = State(initialValue: option.scheduledWeekdaysMask)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Edit Card Option").font(.title2.weight(.semibold))
            TextField("Option name", text: $name).textFieldStyle(.roundedBorder)
            VStack(alignment: .leading, spacing: 8) {
                Text("Default Days").font(.headline)
                Text("Days may remain unassigned. Assigning a day here removes it from another option in this card.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(RoutineWeekday.allCases) { weekday in
                        let selected = RoutineSchedule.contains(weekday, in: weekdaysMask)
                        Button {
                            weekdaysMask = RoutineSchedule.toggling(weekday, in: weekdaysMask)
                        } label: {
                            Text(weekday.shortName)
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 28)
                                .background(selected ? JournalPalette.raised : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                                .foregroundStyle(selected ? JournalPalette.ink : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 470)
    }

    private func save() {
        do {
            try TodayCardsStore.updateOption(
                option,
                name: name,
                scheduledWeekdaysMask: weekdaysMask,
                allOptions: allOptions,
                history: history,
                in: modelContext
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct GroupedRoutineChecklist: View {
    @Environment(\.modelContext) private var modelContext
    let routine: Routine
    let date: Date
    let edit: () -> Void
    let archive: (() -> Void)?
    let reportError: (String) -> Void
    private var orderedSteps: [NightRoutineStep] { routine.steps.sorted { $0.order < $1.order } }
    private var completedCount: Int { RoutineGroupCompletionStore.completedStepCount(for: routine, on: date) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(routine.title, systemImage: routine.iconName).font(.headline)
                Spacer()
                Button("Edit", systemImage: "pencil", action: edit)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(JournalPalette.raised)
                    .frame(minWidth: 28, minHeight: 28)
                    .help("Edit card")
                if let archive {
                    Button("Archive", systemImage: "archivebox", action: archive)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .foregroundStyle(JournalPalette.raised)
                        .frame(minWidth: 28, minHeight: 28)
                        .help("Archive experiment")
                }
            }
            Text("\(completedCount) of \(orderedSteps.count) complete").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(orderedSteps) { step in
                        let completed = RoutineGroupCompletionStore.isComplete(step, on: date)
                        Button { toggle(step) } label: {
                            HStack(spacing: 9) {
                                Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                                Text(step.title).strikethrough(completed).frame(maxWidth: .infinity, alignment: .leading)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }.frame(maxHeight: 260)
            Button("Complete group", systemImage: "checkmark.seal.fill") { completeGroup() }
                .buttonStyle(.borderedProminent).disabled(completedCount == orderedSteps.count).frame(maxWidth: .infinity, alignment: .trailing)
        }.padding(16).frame(width: 320)
    }
    private func toggle(_ step: NightRoutineStep) {
        do {
            if RoutineGroupCompletionStore.isComplete(step, on: date) {
                try RoutineGroupCompletionStore.uncomplete(step, in: routine, at: date, in: modelContext)
            } else {
                _ = try RoutineGroupCompletionStore.complete(step, in: routine, at: date, in: modelContext)
            }
        } catch { reportError(error.localizedDescription) }
    }
    private func completeGroup() {
        do {
            _ = try RoutineGroupCompletionStore.completeGroup(routine, at: date, in: modelContext)
        } catch { reportError(error.localizedDescription) }
    }
}
