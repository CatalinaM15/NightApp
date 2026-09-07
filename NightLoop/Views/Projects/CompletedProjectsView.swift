import SwiftData
import SwiftUI

struct CompletedProjectsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \NightProject.createdAt, order: .reverse)
    private var projects: [NightProject]

    @State private var pendingDeletion: NightProject?
    @State private var errorMessage: String?

    private var completedProjects: [NightProject] {
        projects
            .filter(\.isCompleted)
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Completed Projects").font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }

            if completedProjects.isEmpty {
                ContentUnavailableView(
                    "No Completed Projects",
                    systemImage: "archivebox",
                    description: Text("Finished projects will rest here.")
                )
            } else {
                List(completedProjects) { project in
                    HStack {
                        Circle()
                            .fill(ProjectAccent.color(for: project.colorTag))
                            .frame(width: 9, height: 9)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(project.name)
                            if let completedAt = project.completedAt {
                                Text(completedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(project.steps.isEmpty ? "Complete" : "\(project.steps.count) steps")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button {
                            pendingDeletion = project
                        } label: {
                            Label("Delete \(project.name)", systemImage: "trash")
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                        .help("Permanently delete project")
                    }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 470, minHeight: 430)
        .confirmationDialog(
            "Delete Project?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Permanently", role: .destructive) { deletePendingProject() }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("This permanently deletes \(pendingDeletion?.name ?? "this project") and all of its steps. This cannot be undone.")
        }
        .alert("Could Not Delete Project", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "The project could not be deleted.")
        }
    }

    private func deletePendingProject() {
        guard let project = pendingDeletion else { return }
        pendingDeletion = nil
        do {
            try ProjectStore.delete(project, in: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
