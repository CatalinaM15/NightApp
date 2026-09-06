import Foundation
import SwiftData

enum ProjectStoreError: LocalizedError, Equatable {
    case emptyProjectName
    case duplicateProjectName
    case emptyStepTitle
    case duplicateStepTitle
    case invalidWeek
    case weekIsFull

    var errorDescription: String? {
        switch self {
        case .emptyProjectName: "A project needs a name."
        case .duplicateProjectName: "A project with this name already exists."
        case .emptyStepTitle: "A step needs a title."
        case .duplicateStepTitle: "This project already contains that step."
        case .invalidWeek: "Choose a week from 1 through 4."
        case .weekIsFull: "Each week can contain up to three steps."
        }
    }
}

@MainActor
enum ProjectStore {
    @discardableResult
    static func create(
        name: String,
        colorTag: String?,
        at date: Date = .now,
        in context: ModelContext
    ) throws -> NightProject {
        let normalizedName = try validatedProjectName(name, excluding: nil, in: context)
        let project = NightProject(name: normalizedName, createdAt: date, colorTag: colorTag)
        context.insert(project)
        try context.save()
        return project
    }

    static func update(
        _ project: NightProject,
        name: String,
        colorTag: String?,
        in context: ModelContext
    ) throws {
        project.name = try validatedProjectName(name, excluding: project.id, in: context)
        project.colorTag = colorTag
        try context.save()
    }

    @discardableResult
    static func addStep(
        to project: NightProject,
        title: String,
        weekNumber: Int,
        in context: ModelContext
    ) throws -> ProjectStep {
        let normalizedTitle = try validatedStepTitle(title, excluding: nil, in: project)
        try validateWeek(weekNumber, excluding: nil, in: project)
        let step = ProjectStep(
            title: normalizedTitle,
            order: (project.steps.map(\.order).max() ?? -1) + 1,
            weekNumber: weekNumber
        )
        context.insert(step)
        project.steps.append(step)
        normalizeOrder(in: project)
        try context.save()
        return step
    }

    static func updateStep(
        _ step: ProjectStep,
        title: String,
        weekNumber: Int,
        in context: ModelContext
    ) throws {
        guard let project = step.project else { return }
        step.title = try validatedStepTitle(title, excluding: step.id, in: project)
        try validateWeek(weekNumber, excluding: step.id, in: project)
        step.weekNumber = weekNumber
        normalizeOrder(in: project)
        try context.save()
    }

    static func moveStep(
        _ step: ProjectStep,
        by offset: Int,
        in context: ModelContext
    ) throws {
        guard let project = step.project else { return }
        var weekSteps = project.steps
            .filter { $0.weekNumber == step.weekNumber }
            .sorted { $0.order < $1.order }
        guard let source = weekSteps.firstIndex(where: { $0.id == step.id }) else { return }
        let destination = source + offset
        guard weekSteps.indices.contains(destination) else { return }
        weekSteps.swapAt(source, destination)

        let positions = project.steps
            .filter { $0.weekNumber == step.weekNumber }
            .map(\.order)
            .sorted()
        for (item, order) in zip(weekSteps, positions) { item.order = order }
        normalizeOrder(in: project)
        try context.save()
    }

    private static func validatedProjectName(
        _ name: String,
        excluding id: UUID?,
        in context: ModelContext
    ) throws -> String {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw ProjectStoreError.emptyProjectName }
        let projects = try context.fetch(FetchDescriptor<NightProject>())
        guard !projects.contains(where: {
            $0.id != id && $0.name.compare(normalized, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) else { throw ProjectStoreError.duplicateProjectName }
        return normalized
    }

    private static func validatedStepTitle(
        _ title: String,
        excluding id: UUID?,
        in project: NightProject
    ) throws -> String {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw ProjectStoreError.emptyStepTitle }
        guard !project.steps.contains(where: {
            $0.id != id && $0.title.compare(normalized, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) else { throw ProjectStoreError.duplicateStepTitle }
        return normalized
    }

    private static func validateWeek(
        _ weekNumber: Int,
        excluding id: UUID?,
        in project: NightProject
    ) throws {
        guard (1...4).contains(weekNumber) else { throw ProjectStoreError.invalidWeek }
        let count = project.steps.filter { $0.weekNumber == weekNumber && $0.id != id }.count
        guard count < 3 else { throw ProjectStoreError.weekIsFull }
    }

    private static func normalizeOrder(in project: NightProject) {
        let ordered = project.steps.sorted {
            if $0.weekNumber != $1.weekNumber { return $0.weekNumber < $1.weekNumber }
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        for (index, step) in ordered.enumerated() { step.order = index }
    }
}
