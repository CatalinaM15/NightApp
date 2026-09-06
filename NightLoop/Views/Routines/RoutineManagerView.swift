import SwiftData
import SwiftUI

struct RoutineManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Routine.sortOrder), SortDescriptor(\Routine.title)])
    private var routines: [Routine]

    let date: Date
    @State private var editingRoutine: Routine?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Manage Routines")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            if routines.isEmpty {
                ContentUnavailableView("No Routines", systemImage: "moon.stars")
            } else {
                List {
                    Section("Active") {
                        ForEach(routines.filter(\.isActive)) { routine in
                            row(for: routine)
                        }
                    }
                    Section("Inactive") {
                        ForEach(routines.filter { !$0.isActive }) { routine in
                            row(for: routine)
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 470, minHeight: 430)
        .sheet(item: $editingRoutine) { routine in
            RoutineEditorView(
                title: "Edit Routine",
                initialTitle: routine.title,
                initialIcon: routine.iconName,
                initialScheduledWeekdaysMask: routine.scheduledWeekdaysMask
            ) { title, icon, weekdays in
                try RoutineStore.update(
                    routine,
                    title: title,
                    iconName: icon,
                    scheduledWeekdaysMask: weekdays,
                    in: modelContext
                )
            }
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

    @ViewBuilder
    private func row(for routine: Routine) -> some View {
        HStack {
            Label(routine.title, systemImage: routine.iconName)
            Spacer()
            if routine.isActive {
                Button("Move Up", systemImage: "chevron.up") { perform { try RoutineStore.move(routine, by: -1, in: modelContext) } }
                    .labelStyle(.iconOnly)
                    .help("Move up")
                Button("Move Down", systemImage: "chevron.down") { perform { try RoutineStore.move(routine, by: 1, in: modelContext) } }
                    .labelStyle(.iconOnly)
                    .help("Move down")
                Button("Edit") { editingRoutine = routine }
                Button("Disable") { perform { try RoutineStore.disable(routine, in: modelContext) } }
            } else {
                Button("Edit") { editingRoutine = routine }
                Button("Reactivate") {
                    perform { try RoutineStore.reactivate(routine, on: date, in: modelContext) }
                }
            }
        }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { errorMessage = error.localizedDescription }
    }
}
