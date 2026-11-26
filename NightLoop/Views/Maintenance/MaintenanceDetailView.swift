import SwiftData
import SwiftUI

struct MaintenanceDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let item: MaintenanceItem
    let kind: MaintenanceKind
    @ObservedObject var undoCoordinator: CompletionUndoCoordinator
    @State private var recordDate = Date.now
    @State private var showsEditor = false
    @State private var editingRecord: MaintenanceRecord?
    @State private var deletingRecord: MaintenanceRecord?
    @State private var confirmsDeletion = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(item.title).font(.title2.weight(.semibold))
                Spacer()
                Button("Close") { dismiss() }
            }
            HStack {
                Text(MaintenanceFrequency(rawValue: item.frequency)?.title ?? item.frequency)
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Button("Edit", systemImage: "pencil") { showsEditor = true }
            }
            Text(kind == .chores ? item.elapsedText(on: .now) : "Last visit: \(item.elapsedText(on: .now))")
                .font(.subheadline)
            DatePicker(kind == .chores ? "Completed on" : "Visit date", selection: $recordDate, in: ...Date.now, displayedComponents: .date)
            Button(kind.recordAction, systemImage: "checkmark.circle") { record() }
                .disabled(item.isRecorded(on: recordDate))
            Text("History").font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if item.records.isEmpty { Text("No dates recorded yet.").foregroundStyle(.secondary) }
                    ForEach(item.records.sorted { $0.date > $1.date }) { record in
                        HStack {
                            Text(record.date.formatted(date: .abbreviated, time: .omitted))
                            Spacer()
                            Button("Edit date", systemImage: "pencil") { editingRecord = record }
                                .labelStyle(.iconOnly).buttonStyle(.borderless)
                            Button("Remove date", systemImage: "trash", role: .destructive) { deletingRecord = record }
                                .labelStyle(.iconOnly).buttonStyle(.borderless)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 230)
            if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red) }
            Button("Delete \(kind.itemName)", role: .destructive) { confirmsDeletion = true }
            if let message = undoCoordinator.message {
                UndoToast(message: message, undo: undoCoordinator.undo)
            }
        }
        .padding(24)
        .frame(width: 420)
        .foregroundStyle(Color.primary)
        .background(.background)
        .sheet(isPresented: $showsEditor) { MaintenanceEditorView(kind: kind, item: item) }
        .sheet(item: $editingRecord) { record in
            MaintenanceRecordEditor(record: record, undoCoordinator: undoCoordinator)
        }
        .confirmationDialog("Delete \(item.title)?", isPresented: $confirmsDeletion, titleVisibility: .visible) {
            Button("Delete \(kind.itemName) and History", role: .destructive) {
                do {
                    undoCoordinator.clear()
                    try MaintenanceStore.delete(item, in: modelContext)
                    dismiss()
                } catch { errorMessage = error.localizedDescription }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This permanently removes the entry and all its recorded dates.") }
        .confirmationDialog("Remove this date?", isPresented: Binding(
            get: { deletingRecord != nil }, set: { if !$0 { deletingRecord = nil } }
        ), titleVisibility: .visible, presenting: deletingRecord) { record in
            Button("Remove Date", role: .destructive) {
                do {
                    undoCoordinator.clear()
                    try MaintenanceStore.removeRecord(id: record.id, in: modelContext)
                    deletingRecord = nil
                } catch { errorMessage = error.localizedDescription }
            }
            Button("Cancel", role: .cancel) { deletingRecord = nil }
        } message: { _ in Text("The other history dates will be kept.") }
    }

    private func record() {
        do {
            let record = try MaintenanceStore.record(item, on: recordDate, in: modelContext)
            let recordID = record.id
            undoCoordinator.offer(message: kind == .chores ? "Recorded \(item.title)" : "Recorded visit to \(item.title)") {
                do { try MaintenanceStore.removeRecord(id: recordID, in: modelContext) }
                catch { errorMessage = error.localizedDescription }
            }
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct MaintenanceRecordEditor: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let record: MaintenanceRecord
    @ObservedObject var undoCoordinator: CompletionUndoCoordinator
    @State private var date: Date
    @State private var errorMessage: String?

    init(record: MaintenanceRecord, undoCoordinator: CompletionUndoCoordinator) {
        self.record = record
        self.undoCoordinator = undoCoordinator
        _date = State(initialValue: record.date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Recorded Date").font(.title2.weight(.semibold))
            DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
            if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    do {
                        try MaintenanceStore.updateDate(record, to: date, in: modelContext)
                        undoCoordinator.clear()
                        dismiss()
                    } catch { errorMessage = error.localizedDescription }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 360)
        .foregroundStyle(Color.primary)
        .background(.background)
    }
}
