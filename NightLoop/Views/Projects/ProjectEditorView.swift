import SwiftUI

struct ProjectEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let heading: String
    let save: (String, String?) throws -> Void

    @State private var name: String
    @State private var colorTag: String?
    @State private var errorMessage: String?

    private let colors = ["garnet", "ember", "gold", "forest", "slate"]

    init(
        heading: String,
        initialName: String = "",
        initialColorTag: String? = "garnet",
        save: @escaping (String, String?) throws -> Void
    ) {
        self.heading = heading
        self.save = save
        _name = State(initialValue: initialName)
        _colorTag = State(initialValue: initialColorTag)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(heading).font(.title2.weight(.semibold))
            TextField("Project name", text: $name)
                .textFieldStyle(.roundedBorder)
            Text("Accent").font(.headline)
            HStack(spacing: 12) {
                ForEach(colors, id: \.self) { tag in
                    Button {
                        colorTag = tag
                    } label: {
                        Circle()
                            .fill(ProjectAccent.color(for: tag))
                            .frame(width: 24, height: 24)
                            .overlay {
                                if colorTag == tag {
                                    Image(systemName: "checkmark")
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(tag) accent")
                    .accessibilityValue(colorTag == tag ? "Selected" : "Not selected")
                    .accessibilityAddTraits(colorTag == tag ? .isSelected : [])
                }
            }
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { performSave() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 390)
    }

    private func performSave() {
        do {
            try save(name, colorTag)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

enum ProjectAccent {
    static func color(for tag: String?) -> Color {
        JournalPalette.projectAccent(for: tag)
    }
}
