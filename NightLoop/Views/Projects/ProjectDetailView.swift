import SwiftData
import SwiftUI

struct ProjectDetailView: View {
    @Environment(\.modelContext) private var modelContext

    let project: NightProject
    let activeProjects: [NightProject]
    let selectProject: (UUID) -> Void
    let showCompletedProjects: () -> Void
    let createProject: () -> Void
    @ObservedObject var undoCoordinator: CompletionUndoCoordinator

    @State private var showsProjectEditor = false
    @State private var showsProjectSwitcher = false
    @State private var showsNewStep = false
    @State private var editingStep: ProjectStep?
    @State private var errorMessage: String?

    private var orderedSteps: [ProjectStep] {
        project.steps.sorted { $0.order < $1.order }
    }

    private var usedWeeks: [Int] {
        Array(Set(orderedSteps.map(\.weekNumber))).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            projectHeader

            if project.steps.isEmpty {
                emptyProjectCompletion
            } else {
                progress
                ForEach(usedWeeks, id: \.self) { week in
                    weekSection(week)
                }
            }
        }
        .sheet(isPresented: $showsProjectEditor) {
            ProjectEditorView(
                heading: "Edit Project",
                initialName: project.name,
                initialColorTag: project.colorTag
            ) { name, colorTag in
                try ProjectStore.update(project, name: name, colorTag: colorTag, in: modelContext)
            }
        }
        .sheet(isPresented: $showsNewStep) {
            ProjectStepEditorView(heading: "New Step", initialWeekNumber: suggestedWeek) { title, week in
                try ProjectStore.addStep(to: project, title: title, weekNumber: week, in: modelContext)
            }
        }
        .sheet(item: $editingStep) { step in
            ProjectStepEditorView(
                heading: "Edit Step",
                initialTitle: step.title,
                initialWeekNumber: step.weekNumber
            ) { title, week in
                try ProjectStore.updateStep(step, title: title, weekNumber: week, in: modelContext)
            }
        }
        .alert("Project Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "The project could not be updated.")
        }
    }

    private var projectHeader: some View {
        HStack {
            Button {
                showsProjectSwitcher.toggle()
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(ProjectAccent.color(for: project.colorTag))
                        .frame(width: 9, height: 9)
                    Text(project.name)
                        .font(.headline)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Switch project")
            .popover(isPresented: $showsProjectSwitcher, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(activeProjects) { candidate in
                        Button {
                            selectProject(candidate.id)
                            showsProjectSwitcher = false
                        } label: {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(ProjectAccent.color(for: candidate.colorTag))
                                    .frame(width: 9, height: 9)
                                Text(candidate.name)
                                Spacer()
                                if candidate.id == project.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                    }
                }
                .padding(8)
                .frame(minWidth: 220)
            }
            Spacer()
            Button {
                showsProjectEditor = true
            } label: {
                Label("Edit Project", systemImage: "pencil")
            }
            .labelStyle(.iconOnly)
            .help("Edit project")
            Button(action: showCompletedProjects) {
                Label("Completed Projects", systemImage: "archivebox")
            }
            .labelStyle(.iconOnly)
            .help("Completed projects")
            Button {
                showsNewStep = true
            } label: {
                Label("Add Step", systemImage: "plus.circle")
            }
            .labelStyle(.iconOnly)
            .help("Add step")
            Button(action: createProject) {
                Label("New Project", systemImage: "plus")
            }
            .labelStyle(.iconOnly)
            .help("New project")
        }
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 5) {
            ProgressView(value: Double(project.completedStepCount), total: Double(project.steps.count))
                .tint(ProjectAccent.color(for: project.colorTag))
            Text("\(project.completedStepCount) of \(project.steps.count) steps")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var emptyProjectCompletion: some View {
        Button {
            completeEmptyProject()
        } label: {
            Label("Complete project", systemImage: "circle")
        }
        .buttonStyle(.plain)
        .help("This project has no steps, so it can be completed directly")
    }

    private func weekSection(_ week: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Week \(week)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            ForEach(orderedSteps.filter { $0.weekNumber == week }) { step in
                ProjectStepRow(
                    step: step,
                    complete: { complete(step) },
                    edit: { editingStep = step },
                    moveUp: { perform { try ProjectStore.moveStep(step, by: -1, in: modelContext) } },
                    moveDown: { perform { try ProjectStore.moveStep(step, by: 1, in: modelContext) } }
                )
            }
        }
    }

    private var suggestedWeek: Int {
        usedWeeks.last ?? 1
    }

    private func complete(_ step: ProjectStep) {
        perform {
            try ProjectCompletionStore.complete(step, in: modelContext)
            let completedProject = project.isCompleted
            undoCoordinator.offer(
                message: completedProject ? "Completed \(project.name)" : "Completed step"
            ) {
                perform { try ProjectCompletionStore.undo(step, in: modelContext) }
            }
        }
    }

    private func completeEmptyProject() {
        perform {
            try ProjectCompletionStore.completeEmptyProject(project, in: modelContext)
            undoCoordinator.offer(message: "Completed \(project.name)") {
                perform { try ProjectCompletionStore.undoEmptyProject(project, in: modelContext) }
            }
        }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { errorMessage = error.localizedDescription }
    }
}

private struct ProjectStepRow: View {
    let step: ProjectStep
    let complete: () -> Void
    let edit: () -> Void
    let moveUp: () -> Void
    let moveDown: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: complete) {
                Image(systemName: step.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.body)
            }
            .buttonStyle(.plain)
            .disabled(step.isCompleted)
            .accessibilityLabel(step.isCompleted ? "\(step.title), completed" : "Complete \(step.title)")

            Text(step.title)
                .strikethrough(step.isCompleted)
                .foregroundStyle(step.isCompleted ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !step.isCompleted {
                Menu {
                    Button("Edit", systemImage: "pencil", action: edit)
                    Button("Move Up", systemImage: "chevron.up", action: moveUp)
                    Button("Move Down", systemImage: "chevron.down", action: moveDown)
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Step options")
            }
        }
        .padding(.vertical, 3)
    }
}
