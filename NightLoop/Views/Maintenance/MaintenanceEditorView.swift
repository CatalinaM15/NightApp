import SwiftData
import SwiftUI

struct MaintenanceEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let kind: MaintenanceKind
    let item: MaintenanceItem?
    @State private var title: String
    @State private var isBatch = false
    @State private var batchText = ""
    @State private var frequency: MaintenanceFrequency
    @State private var weekday: Int
    @State private var recordsLastDate = false
    @State private var lastDate = Date.now
    @State private var errorMessage: String?
    @FocusState private var nameFocused: Bool

    init(kind: MaintenanceKind, item: MaintenanceItem? = nil, initialFrequency: MaintenanceFrequency = .monthly, initialWeekday: Int = 0) {
        self.kind = kind
        self.item = item
        _title = State(initialValue: item?.title ?? "")
        _frequency = State(initialValue: item.flatMap { MaintenanceFrequency(rawValue: $0.frequency) } ?? initialFrequency)
        _weekday = State(initialValue: item?.weekday ?? initialWeekday)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isBatch ? "Batch Add \(kind == .chores ? "Chores" : "Doctors")" : "\(item == nil ? "Add" : "Edit") \(kind.itemName)")
                .font(.title2.weight(.semibold))
            if item == nil { Toggle("Batch add", isOn: $isBatch) }
            if isBatch {
                Text(kind == .chores
                     ? "Use day or frequency headings, then one chore per line. For example: Monday: followed by Laundry, or Monthly: followed by Clean oven."
                     : "Add doctors under Monthly, Every 3 Months, Every 6 Months, and Yearly. All groups are saved together.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Insert Schedule Template") {
                    batchText = MaintenanceBatchParser.template(for: kind)
                    nameFocused = true
                }
                .buttonStyle(.link)
                .disabled(!batchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                TextEditor(text: $batchText)
                    .frame(height: kind == .doctorVisits ? 180 : 140)
                    .border(Color.secondary.opacity(0.3))
                    .focused($nameFocused)
                    .accessibilityLabel("\(kind == .chores ? "Chores" : "Doctors"), with schedule headings")
                if let parsingError {
                    Text(parsingError).font(.caption).foregroundStyle(.red)
                } else if !batchEntries.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Preview (\(batchEntries.count))").font(.caption.weight(.semibold))
                        ScrollView {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(Array(batchEntries.enumerated()), id: \.offset) { _, entry in
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(entry.title).frame(maxWidth: .infinity, alignment: .leading)
                                        Text(entry.scheduleTitle).foregroundStyle(.secondary)
                                    }
                                    .font(.caption)
                                }
                            }
                        }
                        .frame(maxHeight: 100)
                    }
                }
            } else {
                TextField(kind == .chores ? "Chore name" : "Doctor or specialty", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .focused($nameFocused)
            }
            Picker(isBatch ? "Default frequency" : "Frequency", selection: $frequency) {
                ForEach(kind.frequencies) { frequency in Text(frequency.title).tag(frequency) }
            }
            if frequency == .weekly {
                Picker(isBatch ? "Default day" : "Day", selection: $weekday) {
                    ForEach(RoutineWeekday.allCases) { day in Text(day.fullName).tag(day.rawValue) }
                }
            }
            if isBatch {
                Text("Lines without a heading use the defaults above. Headings apply until the next heading.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if item == nil {
                Toggle(kind == .chores ? "Add last completion date" : "Add last visit date", isOn: $recordsLastDate)
                if recordsLastDate {
                    if isBatch {
                        Text("This date will be recorded for every entry.").font(.caption).foregroundStyle(.secondary)
                    }
                    DatePicker(kind == .chores ? "Last done" : "Last visit", selection: $lastDate, in: ...Date.now, displayedComponents: .date)
                }
            }
            if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red) }
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if item == nil && !isBatch {
                    Button("Save & Add Another") { save(addAnother: true) }.disabled(!canSave)
                }
                Button(isBatch ? "Add \(batchEntries.count)" : "Save") { save(addAnother: false) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(24)
        .frame(width: 440)
        .foregroundStyle(Color.primary)
        .background(.background)
        .onAppear { nameFocused = true }
        .onChange(of: isBatch) { _, enabled in
            if enabled && kind == .doctorVisits && batchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                batchText = MaintenanceBatchParser.template(for: .doctorVisits)
                nameFocused = true
            }
        }
    }

    private var parsedBatch: Result<[MaintenanceBatchEntry], Error> {
        Result { try MaintenanceBatchParser.parse(batchText, kind: kind, defaultFrequency: frequency, defaultWeekday: weekday) }
    }
    private var batchEntries: [MaintenanceBatchEntry] { (try? parsedBatch.get()) ?? [] }
    private var parsingError: String? {
        if case let .failure(error) = parsedBatch { return error.localizedDescription }
        return nil
    }
    private var canSave: Bool {
        isBatch ? !batchEntries.isEmpty : !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save(addAnother: Bool) {
        do {
            if let item {
                try MaintenanceStore.update(item, title: title, frequency: frequency, weekday: weekday, in: modelContext)
            } else if isBatch {
                try MaintenanceStore.createBatch(entries: try parsedBatch.get(), kind: kind,
                                                 lastDate: recordsLastDate ? lastDate : nil, in: modelContext)
            } else {
                try MaintenanceStore.create(title: title, kind: kind, frequency: frequency, weekday: weekday,
                                            lastDate: recordsLastDate ? lastDate : nil, in: modelContext)
            }
            if addAnother {
                title = ""
                recordsLastDate = false
                errorMessage = nil
                nameFocused = true
            } else { dismiss() }
        } catch { errorMessage = error.localizedDescription }
    }
}
