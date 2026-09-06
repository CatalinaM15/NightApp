import SwiftData
import SwiftUI

struct ProjectEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let project: NightProject

    @State private var name: String
    @State private var colorTag: String?
    @State private var steps: [ProjectStepEdit]
    @State private var pendingDeletion: ProjectStepEdit?
    @State private var errorMessage: String?

    private let colors = ["garnet", "ember", "gold", "forest", "slate"]

    init(project: NightProject) {
        self.project = project
        _name = State(initialValue: project.name)
        _colorTag = State(initialValue: project.colorTag)
        _steps = State(initialValue: project.steps
            .sorted { $0.order < $1.order }
            .map { ProjectStepEdit(id: $0.id, title: $0.title, weekNumber: $0.weekNumber) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Edit Project").font(.title2.weight(.semibold))
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }

            TextField("Project name", text: $name)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 12) {
                Text("Accent").font(.headline)
                ForEach(colors, id: \.self) { tag in
                    Button {
                        colorTag = tag
                    } label: {
                        Circle()
                            .fill(ProjectAccent.color(for: tag))
                            .frame(width: 22, height: 22)
                            .overlay {
                                if colorTag == tag {
                                    Image(systemName: "checkmark")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.white)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(tag) accent")
                    .accessibilityAddTraits(colorTag == tag ? .isSelected : [])
                }
            }

            Divider()

            Text("Steps").font(.headline)
            if steps.isEmpty {
                ContentUnavailableView(
                    "No Steps",
                    systemImage: "checklist",
                    description: Text("Save to keep this as a project-level task.")
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(1...4, id: \.self) { week in
                            if steps.contains(where: { $0.weekNumber == week }) {
                                VStack(alignment: .leading, spacing: 7) {
                                    Text("Week \(week)")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .textCase(.uppercase)
                                    ForEach(steps.filter { $0.weekNumber == week }) { step in
                                        editRow(step)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            if willCompleteProject {
                Label(
                    "Removing the remaining unfinished work will complete this project.",
                    systemImage: "checkmark.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(22)
        .frame(minWidth: 540, minHeight: 560)
        .alert("Delete Step?", isPresented: Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        ), presenting: pendingDeletion) { step in
            Button("Delete", role: .destructive) {
                steps.removeAll { $0.id == step.id }
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: { step in
            Text("“\(step.title)” will be removed when you save the project.")
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        steps.allSatisfy { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var willCompleteProject: Bool {
        guard !steps.isEmpty else { return false }
        let retainedIDs = Set(steps.map(\.id))
        let retainedModels = project.steps.filter { retainedIDs.contains($0.id) }
        return retainedModels.count == steps.count && retainedModels.allSatisfy(\.isCompleted)
    }

    private func editRow(_ step: ProjectStepEdit) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .help("Drag to reorder within Week \(step.weekNumber)")
            TextField("Step title", text: binding(for: step.id).title)
                .textFieldStyle(.roundedBorder)
            Picker("Week", selection: binding(for: step.id).weekNumber) {
                ForEach(1...4, id: \.self) { Text("W\($0)").tag($0) }
            }
            .labelsHidden()
            .frame(width: 66)
            Button {
                pendingDeletion = step
            } label: {
                Label("Delete Step", systemImage: "trash")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
        }
        .contentShape(Rectangle())
        .draggable(step.id.uuidString)
        .dropDestination(for: String.self) { identifiers, _ in
            guard let identifier = identifiers.first,
                  let draggedID = UUID(uuidString: identifier) else { return false }
            return move(draggedID, before: step.id)
        }
    }

    private func binding(for id: UUID) -> Binding<ProjectStepEdit> {
        Binding(
            get: { steps.first(where: { $0.id == id })! },
            set: { updated in
                guard let index = steps.firstIndex(where: { $0.id == id }) else { return }
                steps[index] = updated
            }
        )
    }

    private func move(_ draggedID: UUID, before targetID: UUID) -> Bool {
        guard draggedID != targetID,
              let source = steps.firstIndex(where: { $0.id == draggedID }),
              let target = steps.firstIndex(where: { $0.id == targetID }),
              steps[source].weekNumber == steps[target].weekNumber else { return false }

        let moved = steps.remove(at: source)
        steps.insert(moved, at: min(target, steps.endIndex))
        return true
    }

    private func save() {
        do {
            try ProjectStore.applyEdits(
                to: project,
                name: name,
                colorTag: colorTag,
                orderedSteps: steps,
                in: modelContext
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
