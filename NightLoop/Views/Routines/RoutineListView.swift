import SwiftData
import SwiftUI

struct RoutineListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Routine.sortOrder), SortDescriptor(\Routine.title)])
    private var routines: [Routine]

    let date: Date
    @ObservedObject var undoCoordinator: CompletionUndoCoordinator

    @State private var errorMessage: String?

    private var activeRoutines: [Routine] { routines.filter(\.isActive) }
    private var dayKey: String { CivilDay(date: date).key }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { index in
                if activeRoutines.indices.contains(index), activeRoutines[index].isScheduled(on: date) {
                    RoutineTile(
                        routine: activeRoutines[index],
                        date: date,
                        dayKey: dayKey,
                        undoCoordinator: undoCoordinator,
                        reportError: { errorMessage = $0 }
                    )
                } else {
                    EmptyRoutineSlot(position: index + 1)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Today's Cards strip")
        .alert("Routine Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "The routine could not be updated.")
        }
    }
}

private struct EmptyRoutineSlot: View {
    let position: Int

    var body: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(JournalPalette.paperRule.opacity(0.12))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(JournalPalette.paperRule.opacity(0.32), style: StrokeStyle(lineWidth: 0.7, dash: [3]))
            }
            .frame(maxWidth: .infinity, minHeight: 76)
            .accessibilityLabel("Empty ritual position \(position)")
    }
}

private struct RoutineTile: View {
    @Environment(\.modelContext) private var modelContext

    let routine: Routine
    let date: Date
    let dayKey: String
    @ObservedObject var undoCoordinator: CompletionUndoCoordinator
    let reportError: (String) -> Void

    @State private var showsGroup = false

    private var isParentCompleted: Bool {
        routine.completions.contains { $0.dayKey == dayKey }
    }

    private var completionUnits: (completed: Int, total: Int) {
        routine.isGrouped
            ? (RoutineGroupCompletionStore.completedStepCount(for: routine, on: date), routine.steps.count)
            : (isParentCompleted ? 1 : 0, 1)
    }

    private var progress: Double {
        guard completionUnits.total > 0 else { return 0 }
        return min(max(Double(completionUnits.completed) / Double(completionUnits.total), 0), 1)
    }

    var body: some View {
        Button(action: activate) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(JournalPalette.card)
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(JournalPalette.raised.opacity(progress))
                VStack(spacing: 6) {
                    Image(systemName: routine.iconName)
                        .font(.body.weight(.medium))
                    Text(routine.title)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.7)
                }
                .padding(.horizontal, 3)
                .foregroundStyle(progress >= 0.55 ? JournalPalette.ink : JournalPalette.paperInk)
            }
            .frame(maxWidth: .infinity, minHeight: 76)
            .overlay(alignment: .topTrailing) {
                if let streak = RoutineStreakCalculator.currentStreak(for: routine, on: date), streak > 0 {
                    Label("\(streak)", systemImage: "flame.fill")
                        .font(.system(size: 7, weight: .bold))
                        .labelStyle(.titleAndIcon)
                        .padding(3)
                        .foregroundStyle(progress >= 0.55 ? JournalPalette.ink : JournalPalette.ember)
                        .accessibilityLabel("\(streak) scheduled-day streak")
                }
            }
        }
        .buttonStyle(.plain)
        .allowsHitTesting(routine.isGrouped || !isParentCompleted)
        .accessibilityLabel(routine.title)
        .accessibilityValue("\(Int((progress * 100).rounded())) percent complete")
        .popover(isPresented: $showsGroup, arrowEdge: .bottom) {
            GroupedRoutineChecklist(
                routine: routine,
                date: date,
                undoCoordinator: undoCoordinator,
                reportError: reportError
            )
        }
    }

    private func activate() {
        if routine.isGrouped {
            showsGroup = true
        } else {
            do {
                let completion = try RoutineCompletionStore.complete(routine, at: date, in: modelContext)
                undoCoordinator.offer(message: "Completed \(routine.title)") {
                    do { try RoutineCompletionStore.undo(completion, in: modelContext) }
                    catch { reportError(error.localizedDescription) }
                }
            } catch {
                reportError(error.localizedDescription)
            }
        }
    }
}

private struct GroupedRoutineChecklist: View {
    @Environment(\.modelContext) private var modelContext

    let routine: Routine
    let date: Date
    @ObservedObject var undoCoordinator: CompletionUndoCoordinator
    let reportError: (String) -> Void

    private var orderedSteps: [NightRoutineStep] { routine.steps.sorted { $0.order < $1.order } }
    private var completedCount: Int { RoutineGroupCompletionStore.completedStepCount(for: routine, on: date) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(routine.title, systemImage: routine.iconName)
                .font(.headline)
            Text("\(completedCount) of \(orderedSteps.count) complete")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(orderedSteps) { step in
                        let completed = RoutineGroupCompletionStore.isComplete(step, on: date)
                        Button { complete(step) } label: {
                            HStack(spacing: 9) {
                                Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                                Text(step.title)
                                    .strikethrough(completed)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(completed)
                        .accessibilityLabel(completed ? "\(step.title), completed" : "Complete \(step.title)")
                    }
                }
            }
            .frame(maxHeight: 260)

            Button("Complete group", systemImage: "checkmark.seal.fill") { completeGroup() }
                .buttonStyle(.borderedProminent)
                .disabled(completedCount == orderedSteps.count)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(16)
        .frame(width: 300)
    }

    private func complete(_ step: NightRoutineStep) {
        do {
            let change = try RoutineGroupCompletionStore.complete(step, in: routine, at: date, in: modelContext)
            undoCoordinator.offer(message: "Completed \(step.title)") {
                do { try RoutineGroupCompletionStore.undo(change, in: modelContext) }
                catch { reportError(error.localizedDescription) }
            }
        } catch { reportError(error.localizedDescription) }
    }

    private func completeGroup() {
        do {
            let change = try RoutineGroupCompletionStore.completeGroup(routine, at: date, in: modelContext)
            undoCoordinator.offer(message: "Completed \(routine.title)") {
                do { try RoutineGroupCompletionStore.undo(change, in: modelContext) }
                catch { reportError(error.localizedDescription) }
            }
        } catch { reportError(error.localizedDescription) }
    }
}
