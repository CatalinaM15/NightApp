import SwiftData
import SwiftUI

struct MaintenancePage: View {
    @Query(sort: \MaintenanceItem.title) private var items: [MaintenanceItem]
    let kind: MaintenanceKind
    let date: Date
    @ObservedObject var undoCoordinator: CompletionUndoCoordinator
    let close: () -> Void
    @State private var showsNewItem = false
    @State private var newFrequency: MaintenanceFrequency = .monthly
    @State private var selectedItem: MaintenanceItem?
    @State private var selectedDay: RoutineWeekday?

    private var matchingItems: [MaintenanceItem] { items.filter { $0.kind == kind.rawValue } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Button("Home", systemImage: "chevron.left", action: close).buttonStyle(.plain)
                    Spacer()
                    Button("Add \(kind.itemName)", systemImage: "plus") {
                        newFrequency = .monthly
                        showsNewItem = true
                    }
                    .buttonStyle(.plain)
                }
                Label(kind.title, systemImage: kind.iconName).font(JournalTypography.journalTitle)
                ForEach(kind.frequencies) { frequency in
                    JournalSection(title: frequency.title, systemImage: frequency == .weekly ? "calendar" : "clock") {
                        if frequency == .weekly {
                            weeklySchedule
                        } else {
                            let entries = matchingItems.filter { $0.frequency == frequency.rawValue }
                            if entries.isEmpty {
                                Text("No entries yet").font(.caption).foregroundStyle(JournalPalette.paperSecondaryInk)
                            }
                            ForEach(entries) { item in
                                MaintenanceItemRow(item: item, kind: kind, date: date, undoCoordinator: undoCoordinator) {
                                    selectedItem = item
                                }
                            }
                        }
                    } accessory: {
                        Button("Add \(kind.itemName)", systemImage: "plus") {
                            newFrequency = frequency
                            showsNewItem = true
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(JournalIconButtonStyle())
                        .help("Add \(frequency.title.lowercased()) \(kind.itemName.lowercased())")
                    }
                }
            }
            .padding(24)
        }
        .sheet(isPresented: $showsNewItem) {
            MaintenanceEditorView(kind: kind, initialFrequency: newFrequency)
        }
        .sheet(item: $selectedItem) { item in
            MaintenanceDetailView(item: item, kind: kind, undoCoordinator: undoCoordinator)
        }
        .sheet(item: $selectedDay) { day in
            WeeklyChoreDayView(weekday: day, date: date, undoCoordinator: undoCoordinator)
        }
    }

    private var weeklySchedule: some View {
        VStack(spacing: 8) {
            ForEach(RoutineWeekday.allCases) { day in
                let entries = matchingItems.filter { $0.frequency == MaintenanceFrequency.weekly.rawValue && $0.weekday == day.rawValue }
                Button { selectedDay = day } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(day.fullName).font(.caption.weight(.semibold)).frame(width: 80, alignment: .leading)
                        Text(entries.isEmpty ? "No chores" : entries.map(\.title).joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(entries.isEmpty ? JournalPalette.paperSecondaryInk : JournalPalette.paperInk)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right").font(.caption2)
                    }
                    .frame(minHeight: 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("View chores for \(day.fullName)")
            }
        }
    }
}

private struct WeeklyChoreDayView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \MaintenanceItem.title) private var items: [MaintenanceItem]
    let weekday: RoutineWeekday
    let date: Date
    @ObservedObject var undoCoordinator: CompletionUndoCoordinator
    @State private var showsNewItem = false
    @State private var selectedItem: MaintenanceItem?

    private var chores: [MaintenanceItem] {
        items.filter { $0.kind == MaintenanceKind.chores.rawValue && $0.frequency == MaintenanceFrequency.weekly.rawValue && $0.weekday == weekday.rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(weekday.fullName).font(.title2.weight(.semibold))
                Spacer()
                Button("Close") { dismiss() }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if chores.isEmpty { Text("No chores for this day yet.").foregroundStyle(.secondary) }
                    ForEach(chores) { item in
                        MaintenanceItemRow(item: item, kind: .chores, date: date, undoCoordinator: undoCoordinator) {
                            selectedItem = item
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 360)
            Button("Add Chore", systemImage: "plus") { showsNewItem = true }
            if let message = undoCoordinator.message {
                UndoToast(message: message, undo: undoCoordinator.undo)
            }
        }
        .padding(24)
        .frame(width: 420)
        .foregroundStyle(Color.primary)
        .background(.background)
        .sheet(isPresented: $showsNewItem) {
            MaintenanceEditorView(kind: .chores, initialFrequency: .weekly, initialWeekday: weekday.rawValue)
        }
        .sheet(item: $selectedItem) { item in
            MaintenanceDetailView(item: item, kind: .chores, undoCoordinator: undoCoordinator)
        }
    }
}

private struct MaintenanceItemRow: View {
    @Environment(\.modelContext) private var modelContext
    let item: MaintenanceItem
    let kind: MaintenanceKind
    let date: Date
    @ObservedObject var undoCoordinator: CompletionUndoCoordinator
    let open: () -> Void
    @State private var errorMessage: String?

    private var isWeekly: Bool { item.frequency == MaintenanceFrequency.weekly.rawValue }
    private var completed: Bool {
        isWeekly ? item.isRecordedThisWeek(on: date) : item.isRecorded(on: date)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title).multilineTextAlignment(.leading)
                    if !isWeekly {
                        Text(kind == .chores ? item.elapsedText(on: date) : "Last visit: \(item.elapsedText(on: date))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Edit or view history for \(item.title)")
            if kind == .doctorVisits {
                Button("Record Visit", action: open).buttonStyle(.borderless)
            } else {
                Button(completed ? "Done" : "Done Today", systemImage: completed ? "checkmark.circle.fill" : "circle") {
                    do {
                        let record = try MaintenanceStore.record(item, on: .now, in: modelContext)
                        let recordID = record.id
                        undoCoordinator.offer(message: "Completed \(item.title)") {
                            do { try MaintenanceStore.removeRecord(id: recordID, in: modelContext) }
                            catch { errorMessage = error.localizedDescription }
                        }
                    } catch { errorMessage = error.localizedDescription }
                }
                .buttonStyle(.borderless)
                .disabled(completed)
            }
        }
        .alert("Could Not Record Completion", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "Please try again.") }
    }
}
