import AppKit
import EventKit
import SwiftData
import SwiftUI

struct ReminderInboxView: View {
    @Query(sort: \DailyNote.date) private var previousNotes: [DailyNote]
    @AppStorage("copiedInboxNoteIDs") private var copiedNoteIDs = ""
    @SceneStorage("inboxQuickEntryDraft") private var quickEntry = ""
    @StateObject private var viewModel = ReminderInboxViewModel()
    @State private var editingReminder: InboxReminder?
    @ObservedObject var undoCoordinator: CompletionUndoCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            content
            previousNotesSection
        }
        .padding(16)
        .foregroundStyle(JournalPalette.paperInk)
        .journalCard()
        .task(id: viewModel.selectedListID) { await viewModel.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in Task { await viewModel.refresh() } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in Task { await viewModel.refresh() } }
        .sheet(item: $editingReminder) { reminder in
            ReminderEditorView(reminder: reminder, viewModel: viewModel)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label("Inbox", systemImage: "tray")
                .font(JournalTypography.sectionTitle)
            Spacer(minLength: 0)
            if viewModel.authorizationStatus == .fullAccess {
                Picker("List", selection: $viewModel.selectedListID) {
                    Text("Choose a list…").tag("")
                    if !viewModel.selectedListID.isEmpty && viewModel.selectedList == nil {
                        Text("Unavailable list").tag(viewModel.selectedListID)
                    }
                    ForEach(viewModel.lists) { list in
                        Text("\(list.title) · \(list.account)\(list.isWritable ? "" : " (read-only)")").tag(list.id)
                    }
                }
                .labelsHidden()
                .accessibilityLabel("Inbox reminders list")
                .frame(maxWidth: 200)
                .disabled(viewModel.isSaving)
                Button("Refresh Inbox", systemImage: "arrow.clockwise") { Task { await viewModel.refresh() } }
                    .labelStyle(.iconOnly)
                    .buttonStyle(JournalIconButtonStyle())
                    .help("Refresh Inbox")
                    .disabled(viewModel.isLoading)
            }
        }
    }

    @ViewBuilder private var content: some View {
        if let error = viewModel.errorMessage {
            Text(error).font(.caption).foregroundStyle(JournalPalette.paperSecondaryInk)
        }
        switch viewModel.authorizationStatus {
        case .notDetermined:
            Text("Choose a Reminders list to use as your Inbox.").foregroundStyle(JournalPalette.paperSecondaryInk)
            Button(viewModel.isConnecting ? "Connecting…" : "Connect Reminders") { Task { await viewModel.connect() } }
                .disabled(viewModel.isConnecting)
        case .fullAccess:
            connectedContent
        default:
            Text("Reminders access is unavailable. Your local cards and projects still work.")
                .foregroundStyle(JournalPalette.paperSecondaryInk)
            Button("Open Reminders Privacy Settings") { openPrivacySettings() }
            Button("Check Again") { Task { await viewModel.refresh() } }
        }
    }

    private var connectedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.selectedList == nil {
                Text(viewModel.selectedListID.isEmpty
                     ? "Choose the list to display and add reminders to."
                     : "The selected list is unavailable. Choose a list above; nothing will be redirected automatically.")
                    .font(.caption).foregroundStyle(JournalPalette.paperSecondaryInk)
                if viewModel.lists.isEmpty {
                    Text("No Reminders lists are available. Create a list in Reminders, then refresh.")
                        .font(.caption).foregroundStyle(JournalPalette.paperSecondaryInk)
                }
            } else {
                if !viewModel.canWrite {
                    Text("This list is read-only. You can view its reminders, or choose an editable list.")
                        .font(.caption).foregroundStyle(JournalPalette.paperSecondaryInk)
                }
                if viewModel.isLoading && viewModel.reminders.isEmpty {
                    ProgressView("Reading reminders…")
                } else if viewModel.reminders.isEmpty && viewModel.errorMessage == nil {
                    Text("Inbox is clear.").foregroundStyle(JournalPalette.paperSecondaryInk)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(viewModel.reminders) { reminder in
                                reminderRow(reminder)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: CGFloat(max(0, min(viewModel.reminders.count, 3) * 52 - 8)))
                }
                HStack {
                    TextField("Add to Inbox…", text: $quickEntry)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addReminder() }
                        .disabled(!viewModel.canWrite || viewModel.isSaving)
                    Button(viewModel.isSaving ? "Saving…" : "Add", action: addReminder)
                        .disabled(!viewModel.canWrite || viewModel.isSaving || quickEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func reminderRow(_ reminder: InboxReminder) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                Task {
                    if await viewModel.setCompleted(true, identifier: reminder.id) {
                        undoCoordinator.offer(message: "Completed \(reminder.title)") {
                            Task { _ = await viewModel.setCompleted(false, identifier: reminder.id) }
                        }
                    }
                }
            } label: {
                Image(systemName: "circle").frame(minWidth: 24, minHeight: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Complete \(reminder.title)")
            .disabled(!viewModel.canWrite || viewModel.isSaving)
            Button {
                editingReminder = reminder
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(reminder.title)
                        .lineLimit(reminder.dueDate == nil ? 2 : 1)
                        .multilineTextAlignment(.leading)
                    if let due = reminder.dueDate {
                        Text("Due \(due.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption).foregroundStyle(JournalPalette.paperSecondaryInk)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit \(reminder.title)")
            .disabled(!viewModel.canWrite || viewModel.isSaving)
        }
        .frame(height: 44, alignment: .top)
    }

    @ViewBuilder private var previousNotesSection: some View {
        let notes = previousNotes.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !notes.isEmpty {
            DisclosureGroup("Previous notes (\(notes.count))") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Your previous notes are kept here. Copy any note into the selected Inbox list.")
                        .font(.caption).foregroundStyle(JournalPalette.paperSecondaryInk)
                    ForEach(notes, id: \.date) { note in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(note.date.formatted(date: .abbreviated, time: .omitted)).font(.caption.weight(.semibold))
                            Text(note.text).textSelection(.enabled)
                            let noteKey = String(note.date.timeIntervalSinceReferenceDate)
                            let copied = copiedNoteIDs.split(separator: ",").contains(Substring(noteKey))
                            Button(copied ? "Copied to Inbox" : "Copy to Inbox") {
                                Task {
                                    let draft = ReminderDraft(
                                        title: "Note from \(note.date.formatted(date: .abbreviated, time: .omitted))",
                                        notes: note.text,
                                        listID: viewModel.selectedListID,
                                        sourceNoteKey: noteKey
                                    )
                                    if await viewModel.save(draft) {
                                        copiedNoteIDs += (copiedNoteIDs.isEmpty ? "" : ",") + noteKey
                                    }
                                }
                            }
                            .disabled(copied || !viewModel.canWrite || viewModel.isSaving)
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private func addReminder() {
        guard viewModel.canWrite, !viewModel.isSaving else { return }
        let draft = ReminderDraft(title: quickEntry, listID: viewModel.selectedListID)
        Task {
            if await viewModel.save(draft) { quickEntry = "" }
        }
    }

    private func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct ReminderEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let reminder: InboxReminder
    @ObservedObject var viewModel: ReminderInboxViewModel
    @State private var title: String
    @State private var notes: String
    @State private var listID: String

    init(reminder: InboxReminder, viewModel: ReminderInboxViewModel) {
        self.reminder = reminder
        self.viewModel = viewModel
        _title = State(initialValue: reminder.title)
        _notes = State(initialValue: reminder.notes)
        _listID = State(initialValue: reminder.listID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Reminder").font(.title2.weight(.semibold))
            TextField("Reminder title", text: $title).textFieldStyle(.roundedBorder)
            Picker("List", selection: $listID) {
                if !viewModel.lists.contains(where: { $0.id == listID && $0.isWritable }) {
                    Text("Unavailable list").tag(listID)
                }
                ForEach(viewModel.lists.filter(\.isWritable)) { list in
                    Text("\(list.title) · \(list.account)").tag(list.id)
                }
            }
            Text("Notes").font(.headline)
            TextEditor(text: $notes).frame(height: 120).border(Color.secondary.opacity(0.3))
                .accessibilityLabel("Reminder notes")
            if let error = viewModel.errorMessage { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    Task {
                        if await viewModel.save(ReminderDraft(title: title, notes: notes, listID: listID), replacing: reminder.id) {
                            dismiss()
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !viewModel.lists.contains { $0.id == listID && $0.isWritable })
            }
        }
        .disabled(viewModel.isSaving)
        .padding(24)
        .frame(width: 420)
        .foregroundStyle(Color.primary)
        .background(.background)
        .interactiveDismissDisabled(viewModel.isSaving)
    }
}
