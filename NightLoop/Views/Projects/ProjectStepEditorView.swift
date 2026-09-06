import SwiftUI

struct ProjectStepEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let heading: String
    let save: (String, Int) throws -> Void

    @State private var title: String
    @State private var weekNumber: Int
    @State private var errorMessage: String?

    init(
        heading: String,
        initialTitle: String = "",
        initialWeekNumber: Int = 1,
        save: @escaping (String, Int) throws -> Void
    ) {
        self.heading = heading
        self.save = save
        _title = State(initialValue: initialTitle)
        _weekNumber = State(initialValue: initialWeekNumber)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(heading).font(.title2.weight(.semibold))
            TextField("Step description", text: $title)
                .textFieldStyle(.roundedBorder)
            Picker("Week", selection: $weekNumber) {
                ForEach(1...4, id: \.self) { Text("Week \($0)").tag($0) }
            }
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { performSave() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 390)
    }

    private func performSave() {
        do {
            try save(title, weekNumber)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
