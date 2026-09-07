import SwiftData
import SwiftUI

struct RoutineListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Routine.cardSlot) private var routines: [Routine]
    @Query(sort: \CardOption.sortOrder) private var options: [CardOption]
    @Query(sort: \SlotSelectionHistory.date, order: .reverse) private var history: [SlotSelectionHistory]
    let date: Date
    @Binding var planningTomorrow: Bool
    @ObservedObject var undoCoordinator: CompletionUndoCoordinator
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
            GroupedCardTile(slot: 4, fallbackTitle: "Daily Care", routine: TodayCardsStore.routine(forSlot: 4, in: routines), date: date, undoCoordinator: undoCoordinator, reportError: report)
            ForEach(5...7, id: \.self) { slot in
                GroupedCardTile(slot: slot, fallbackTitle: "Experiment \(slot - 4)", routine: TodayCardsStore.routine(forSlot: slot, in: routines), date: date, undoCoordinator: undoCoordinator, reportError: report)
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
            try TodayCardsStore.complete(selection, in: modelContext)
            undoCoordinator.offer(message: "Completed \(selection.optionName)") {
                do { try TodayCardsStore.undoCompletion(selection, in: modelContext) }
                catch { report(error.localizedDescription) }
            }
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
    @State private var handledLongPress = false

    var body: some View {
        Button {
            if handledLongPress { handledLongPress = false; return }
            guard let selection, canComplete else { choose(); return }
            if selection.completedAt == nil { complete(selection) }
        } label: {
            CardTileSurface(title: selection?.optionName ?? "Set up", iconName: category.iconName, progress: selection?.completedAt == nil ? 0 : 1)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in
            handledLongPress = true
            choose()
        })
        .help(selection == nil ? "Choose \(category.title)" : "Tap to complete; hold to change")
        .accessibilityLabel("\(category.title), \(selection?.optionName ?? "not selected")")
    }
}

private struct GroupedCardTile: View {
    @Environment(\.modelContext) private var modelContext
    let slot: Int
    let fallbackTitle: String
    let routine: Routine?
    let date: Date
    @ObservedObject var undoCoordinator: CompletionUndoCoordinator
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
            if routine == nil { showsEditor = true } else { showsChecklist = true }
        } label: {
            CardTileSurface(title: routine?.title ?? fallbackTitle, iconName: routine?.iconName ?? "plus", progress: progress, isEmpty: routine == nil)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showsChecklist, arrowEdge: .bottom) {
            if let routine {
                GroupedRoutineChecklist(
                    routine: routine, date: date, undoCoordinator: undoCoordinator,
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
    @State private var newHobbyName = ""
    @State private var editingOption: CardOption?
    @State private var editedName = ""
    @State private var errorMessage: String?
    private var categoryOptions: [CardOption] { TodayCardsStore.options(for: category, in: options) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(category.title).font(.headline)
            Text(date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(categoryOptions) { option in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Button(option.name) { choose(option) }.buttonStyle(.plain)
                                Spacer()
                                Text(lastPickedText(for: option)).font(.caption2).foregroundStyle(.secondary)
                                if category == .hobby {
                                    Button("Rename", systemImage: "pencil") { editingOption = option; editedName = option.name }
                                        .labelStyle(.iconOnly).buttonStyle(.borderless)
                                }
                            }
                            HStack(spacing: 4) {
                                ForEach(RoutineWeekday.allCases) { weekday in
                                    let selected = RoutineSchedule.contains(weekday, in: option.scheduledWeekdaysMask)
                                    Button(weekday.shortName) {
                                        perform { try TodayCardsStore.setDefault(option: option, weekday: weekday, selected: !selected, allOptions: options, in: modelContext) }
                                    }
                                    .font(.system(size: 8, weight: .semibold)).buttonStyle(.bordered)
                                    .tint(selected ? JournalPalette.raised : Color.clear)
                                }
                            }
                        }
                    }
                }
            }.frame(maxHeight: 310)
            if category == .hobby {
                HStack {
                    TextField("New hobby", text: $newHobbyName)
                    Button("Add") {
                        perform { try TodayCardsStore.addHobbyOption(named: newHobbyName, allOptions: options, in: modelContext); newHobbyName = "" }
                    }.disabled(newHobbyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red) }
        }
        .padding(16).frame(width: 390)
        .alert("Rename Hobby", isPresented: Binding(get: { editingOption != nil }, set: { if !$0 { editingOption = nil } })) {
            TextField("Hobby name", text: $editedName)
            Button("Save") {
                guard let editingOption else { return }
                perform { try TodayCardsStore.renameHobbyOption(editingOption, to: editedName, allOptions: options, history: history, in: modelContext); self.editingOption = nil }
            }
            Button("Cancel", role: .cancel) { editingOption = nil }
        }
    }
    private func lastPickedText(for option: CardOption) -> String {
        guard let days = TodayCardsStore.daysSinceLastPicked(option: option, before: date, history: history) else { return "Never picked" }
        return days == 1 ? "1 day ago" : "\(days) days ago"
    }
    private func perform(_ action: () throws -> Void) { do { try action() } catch { errorMessage = error.localizedDescription } }
}

private struct GroupedRoutineChecklist: View {
    @Environment(\.modelContext) private var modelContext
    let routine: Routine
    let date: Date
    @ObservedObject var undoCoordinator: CompletionUndoCoordinator
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
                Button("Edit", systemImage: "pencil", action: edit).labelStyle(.iconOnly)
                if let archive { Button("Archive", systemImage: "archivebox", action: archive).labelStyle(.iconOnly) }
            }
            Text("\(completedCount) of \(orderedSteps.count) complete").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(orderedSteps) { step in
                        let completed = RoutineGroupCompletionStore.isComplete(step, on: date)
                        Button { complete(step) } label: {
                            HStack(spacing: 9) {
                                Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                                Text(step.title).strikethrough(completed).frame(maxWidth: .infinity, alignment: .leading)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(completed)
                    }
                }
            }.frame(maxHeight: 260)
            Button("Complete group", systemImage: "checkmark.seal.fill") { completeGroup() }
                .buttonStyle(.borderedProminent).disabled(completedCount == orderedSteps.count).frame(maxWidth: .infinity, alignment: .trailing)
        }.padding(16).frame(width: 320)
    }
    private func complete(_ step: NightRoutineStep) {
        do {
            let change = try RoutineGroupCompletionStore.complete(step, in: routine, at: date, in: modelContext)
            undoCoordinator.offer(message: "Completed \(step.title)") {
                do { try RoutineGroupCompletionStore.undo(change, in: modelContext) } catch { reportError(error.localizedDescription) }
            }
        } catch { reportError(error.localizedDescription) }
    }
    private func completeGroup() {
        do {
            let change = try RoutineGroupCompletionStore.completeGroup(routine, at: date, in: modelContext)
            undoCoordinator.offer(message: "Completed \(routine.title)") {
                do { try RoutineGroupCompletionStore.undo(change, in: modelContext) } catch { reportError(error.localizedDescription) }
            }
        } catch { reportError(error.localizedDescription) }
    }
}
