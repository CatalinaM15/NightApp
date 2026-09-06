import SwiftData
import SwiftUI

struct ProjectPickerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \NightProject.createdAt)
    private var projects: [NightProject]

    @ObservedObject var undoCoordinator: CompletionUndoCoordinator

    @State private var selectedProjectID: UUID?
    @State private var showsNewProject = false
    @State private var showsQuickAdd = false
    @State private var showsCompletedProjects = false

    private var activeProjects: [NightProject] {
        projects.filter { !$0.isCompleted }
    }

    private var selectedProject: NightProject? {
        activeProjects.first { $0.id == selectedProjectID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let selectedProject {
                ProjectDetailView(
                    project: selectedProject,
                    activeProjects: activeProjects,
                    selectProject: { selectedProjectID = $0 },
                    showCompletedProjects: { showsCompletedProjects = true },
                    createProject: { showsNewProject = true },
                    quickAddProject: { showsQuickAdd = true },
                    undoCoordinator: undoCoordinator
                )
            } else if activeProjects.isEmpty {
                HStack {
                    Text("Turn tomorrow's intentions into small steps.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        showsCompletedProjects = true
                    } label: {
                        Label("Completed Projects", systemImage: "archivebox")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(JournalIconButtonStyle())
                    .help("Completed projects")
                    Button {
                        showsQuickAdd = true
                    } label: {
                        Label("Quick Add Project", systemImage: "text.badge.plus")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(JournalIconButtonStyle())
                    .help("Quick Add project")
                }
                Button("Create Project") { showsNewProject = true }
            }
        }
        .onAppear(perform: selectFirstProjectIfNeeded)
        .onChange(of: activeProjects.map(\.id)) { _, _ in selectFirstProjectIfNeeded() }
        .sheet(isPresented: $showsNewProject) {
            ProjectEditorView(heading: "New Project") { name, colorTag in
                let project = try ProjectStore.create(name: name, colorTag: colorTag, in: modelContext)
                selectedProjectID = project.id
            }
        }
        .sheet(isPresented: $showsCompletedProjects) {
            CompletedProjectsView()
        }
        .sheet(isPresented: $showsQuickAdd) {
            QuickAddSheetView { project in selectedProjectID = project.id }
        }
    }

    private func selectFirstProjectIfNeeded() {
        if let selectedProjectID,
           activeProjects.contains(where: { $0.id == selectedProjectID }) {
            return
        }
        selectedProjectID = activeProjects.first?.id
    }
}
