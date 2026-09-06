import Foundation
import SwiftData

enum ProjectImportError: LocalizedError, Equatable {
    case invalidPreview(String)

    var errorDescription: String? {
        switch self {
        case .invalidPreview(let message): message
        }
    }
}

@MainActor
enum ProjectImportService {
    @discardableResult
    static func save(
        _ parsed: ParsedProject,
        colorTag: String? = "garnet",
        at date: Date = .now,
        in context: ModelContext
    ) throws -> NightProject {
        let existingNames = try context.fetch(FetchDescriptor<NightProject>()).map(\.name)
        if let issue = QuickAddValidator.validate(parsed, existingProjectNames: existingNames).first {
            throw ProjectImportError.invalidPreview(issue.message)
        }

        let project = NightProject(
            name: parsed.name.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: date,
            colorTag: colorTag
        )
        context.insert(project)

        for (index, parsedStep) in parsed.steps.sorted(by: { $0.order < $1.order }).enumerated() {
            let step = ProjectStep(
                title: parsedStep.title.trimmingCharacters(in: .whitespacesAndNewlines),
                order: index,
                weekNumber: parsedStep.weekNumber
            )
            context.insert(step)
            project.steps.append(step)
        }

        do {
            try context.save()
            return project
        } catch {
            context.rollback()
            throw error
        }
    }
}
