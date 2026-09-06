import SwiftData
import SwiftUI

struct RoutineListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Routine.sortOrder), SortDescriptor(\Routine.title)])
    private var routines: [Routine]

    let date: Date
    @ObservedObject var undoCoordinator: CompletionUndoCoordinator

    @State private var showsNewRoutine = false
    @State private var showsRoutineManager = false
    @State private var errorMessage: String?

    private var activeRoutines: [Routine] { routines.filter(\.isActive) }
    private var dayKey: String { CivilDay(date: date).key }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(activeRoutines.isEmpty ? "Create a small ritual for tonight." : "Complete each ritual once.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
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
                .help("New routine")
            }

            if activeRoutines.isEmpty {
                Button("Create Routine") { showsNewRoutine = true }
            } else {
                ForEach(activeRoutines) { routine in
                    RoutineRowView(
                        routine: routine,
                        isCompleted: routine.completions.contains { $0.dayKey == dayKey },
                        streak: RoutineStreakCalculator.currentStreak(for: routine, on: date),
                        complete: { complete(routine) }
                    )
                }
            }
        }
        .sheet(isPresented: $showsNewRoutine) {
            RoutineEditorView(title: "New Routine") { title, icon in
                try RoutineStore.create(title: title, iconName: icon, on: date, in: modelContext)
            }
        }
        .sheet(isPresented: $showsRoutineManager) {
            RoutineManagerView(date: date)
        }
        .alert("Routine Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "The routine could not be updated.")
        }
    }

    private func complete(_ routine: Routine) {
        do {
            let completion = try RoutineCompletionStore.complete(routine, in: modelContext)
            undoCoordinator.offer(message: "Completed \(routine.title)") {
                do {
                    try RoutineCompletionStore.undo(completion, in: modelContext)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct RoutineRowView: View {
    let routine: Routine
    let isCompleted: Bool
    let streak: Int?
    let complete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: complete) {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isCompleted ? Color(red: 0.24, green: 0.42, blue: 0.25) : JournalPalette.paperSecondaryInk)
            }
            .buttonStyle(.plain)
            .disabled(isCompleted)
            .accessibilityLabel(isCompleted ? "\(routine.title), completed" : "Complete \(routine.title)")
            .frame(minWidth: 28, minHeight: 28)

            Image(systemName: routine.iconName)
                .frame(width: 18)
                .foregroundStyle(.secondary)
            Text(routine.title)
                .strikethrough(isCompleted)
                .foregroundStyle(isCompleted ? .secondary : .primary)
            Spacer()
            if let streak, streak > 0 {
                Label("\(streak)", systemImage: "flame.fill")
                    .font(.caption)
                    .foregroundStyle(JournalPalette.ember)
                    .accessibilityLabel("\(streak) day streak")
            }
        }
        .padding(.vertical, 4)
    }
}
