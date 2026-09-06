import SwiftUI

struct RoutineEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let initialTitle: String
    let initialIcon: String
    let save: (String, String) throws -> Void

    @State private var routineTitle: String
    @State private var iconName: String
    @State private var errorMessage: String?

    private let icons = ["moon.stars", "book.closed", "figure.mind.and.body", "drop", "sparkles", "pencil"]

    init(
        title: String,
        initialTitle: String = "",
        initialIcon: String = "moon.stars",
        save: @escaping (String, String) throws -> Void
    ) {
        self.title = title
        self.initialTitle = initialTitle
        self.initialIcon = initialIcon
        self.save = save
        _routineTitle = State(initialValue: initialTitle)
        _iconName = State(initialValue: initialIcon)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.title2.weight(.semibold))
            TextField("Routine name", text: $routineTitle)
                .textFieldStyle(.roundedBorder)

            Text("Icon")
                .font(.headline)
            HStack {
                ForEach(icons, id: \.self) { icon in
                    Button {
                        iconName = icon
                    } label: {
                        Image(systemName: icon)
                            .frame(width: 28, height: 28)
                            .background(iconName == icon ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(icon)
                    .accessibilityAddTraits(iconName == icon ? .isSelected : [])
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { performSave() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(routineTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 390)
    }

    private func performSave() {
        do {
            try save(routineTitle, iconName)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
