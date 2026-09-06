import SwiftData
import SwiftUI

struct CompletedProjectsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \NightProject.createdAt, order: .reverse)
    private var projects: [NightProject]

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
                    }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 470, minHeight: 430)
    }
}
