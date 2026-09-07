import SwiftData
import SwiftUI

struct ProjectDetailView: View {
    @Environment(\.modelContext) private var modelContext

    let project: NightProject
    let activeProjects: [NightProject]
    let selectProject: (UUID) -> Void
    let showCompletedProjects: () -> Void
    let createProject: () -> Void
    let quickAddProject: () -> Void
    @ObservedObject var undoCoordinator: CompletionUndoCoordinator

    @State private var showsProjectEditor = false
    @State private var showsProjectSwitcher = false
    @State private var showsNewStep = false
    @State private var errorMessage: String?
    @State private var expandedWeeks: Set<Int> = []
    @State private var manuallyToggledWeeks: Set<Int> = []

    private var orderedSteps: [ProjectStep] {
        project.steps.sorted { $0.order < $1.order }
    }

    private var usedWeeks: [Int] {
        Array(Set(orderedSteps.map(\.weekNumber))).sorted()
    }

    private var activeWeek: Int? {
        usedWeeks.first { week in
            orderedSteps.contains { $0.weekNumber == week && !$0.isCompleted }
        }
    }

    private var completionSignature: [String] {
        orderedSteps.map { "\($0.id.uuidString):\($0.isCompleted)" }
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
            ProjectEditView(project: project)
        }
        .sheet(isPresented: $showsNewStep) {
            ProjectStepEditorView(heading: "New Step", initialWeekNumber: suggestedWeek) { title, week in
                try ProjectStore.addStep(to: project, title: title, weekNumber: week, in: modelContext)
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
        .onAppear { resetWeekDisclosureState() }
        .onChange(of: project.id) { _, _ in resetWeekDisclosureState() }
        .onChange(of: completionSignature) { _, _ in applyAutomaticWeekDisclosure() }
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
            .accessibilityHint("Shows the list of active projects")
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
            .buttonStyle(JournalIconButtonStyle())
            .help("Edit project")
            Button(action: showCompletedProjects) {
                Label("Completed Projects", systemImage: "archivebox")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(JournalIconButtonStyle())
            .help("Completed projects")
            Button(action: quickAddProject) {
                Label("Quick Add Project", systemImage: "text.badge.plus")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(JournalIconButtonStyle())
            .help("Quick Add project")
            Button {
                showsNewStep = true
            } label: {
                Label("Add Step", systemImage: "plus.circle")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(JournalIconButtonStyle())
            .help("Add step")
            Button(action: createProject) {
                Label("New Project", systemImage: "plus")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(JournalIconButtonStyle())
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
        .padding(.vertical, 5)
    }

    private func weekSection(_ week: Int) -> some View {
        DisclosureGroup(isExpanded: weekExpansionBinding(for: week)) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(orderedSteps.filter { $0.weekNumber == week }) { step in
                    ProjectStepRow(
                        step: step,
                        complete: { complete(step) }
                    )
                }
            }
            .padding(.top, 4)
        } label: {
            Text("Week \(week)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(JournalPalette.paperSecondaryInk)
                .textCase(.uppercase)
        }
        .tint(JournalPalette.paperSecondaryInk)
    }

    private var suggestedWeek: Int {
        usedWeeks.last ?? 1
    }

    private func weekExpansionBinding(for week: Int) -> Binding<Bool> {
        Binding(
            get: { expandedWeeks.contains(week) },
            set: { isExpanded in
                manuallyToggledWeeks.insert(week)
                if isExpanded {
                    expandedWeeks.insert(week)
                } else {
                    expandedWeeks.remove(week)
                }
            }
        )
    }

    private func resetWeekDisclosureState() {
        manuallyToggledWeeks.removeAll()
        expandedWeeks = activeWeek.map { Set([$0]) } ?? []
    }

    private func applyAutomaticWeekDisclosure() {
        for week in usedWeeks where !manuallyToggledWeeks.contains(week) {
            if week == activeWeek {
                expandedWeeks.insert(week)
            } else {
                expandedWeeks.remove(week)
            }
        }
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

    var body: some View {
        HStack(spacing: 10) {
            Button(action: complete) {
                Image(systemName: step.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.body)
            }
            .buttonStyle(.plain)
            .disabled(step.isCompleted)
            .accessibilityLabel(step.isCompleted ? "\(step.title), completed" : "Complete \(step.title)")
            .frame(minWidth: 28, minHeight: 28)
            .foregroundStyle(step.isCompleted ? Color(red: 0.24, green: 0.42, blue: 0.25) : JournalPalette.paperSecondaryInk)

            Text(step.title)
                .strikethrough(step.isCompleted)
                .foregroundStyle(step.isCompleted ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)

        }
        .padding(.vertical, 3)
    }
}
