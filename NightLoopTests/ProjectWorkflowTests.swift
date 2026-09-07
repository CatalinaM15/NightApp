import SwiftData
import Testing
@testable import NightLoop

@MainActor
struct ProjectWorkflowTests {
    @Test func projectNamesAreUniqueAcrossActiveAndCompletedProjects() throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        let project = try ProjectStore.create(name: "Launch", colorTag: "garnet", in: context)
        try ProjectCompletionStore.completeEmptyProject(project, in: context)

        #expect(throws: ProjectStoreError.duplicateProjectName) {
            try ProjectStore.create(name: " launch ", colorTag: nil, in: context)
        }
    }

    @Test func stepTitlesAreUniqueAcrossTheWholeProject() throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        let project = try ProjectStore.create(name: "Launch", colorTag: nil, in: context)
        try ProjectStore.addStep(to: project, title: "Write copy", weekNumber: 1, in: context)

        #expect(throws: ProjectStoreError.duplicateStepTitle) {
            try ProjectStore.addStep(to: project, title: "WRITE COPY", weekNumber: 2, in: context)
        }
    }

    @Test func eachWeekAcceptsAtMostThreeSteps() throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        let project = try ProjectStore.create(name: "Launch", colorTag: nil, in: context)
        for index in 1...3 {
            try ProjectStore.addStep(to: project, title: "Step \(index)", weekNumber: 1, in: context)
        }

        #expect(throws: ProjectStoreError.weekIsFull) {
            try ProjectStore.addStep(to: project, title: "Step 4", weekNumber: 1, in: context)
        }
    }

    @Test func globalOrderIsNormalizedAcrossWeekGroups() throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        let project = try ProjectStore.create(name: "Launch", colorTag: nil, in: context)
        let weekTwo = try ProjectStore.addStep(to: project, title: "Later", weekNumber: 2, in: context)
        let weekOne = try ProjectStore.addStep(to: project, title: "Sooner", weekNumber: 1, in: context)

        #expect(weekOne.order == 0)
        #expect(weekTwo.order == 1)
        #expect(Set(project.steps.map(\.order)).count == project.steps.count)
    }

    @Test func stepCanMoveWithinItsWeekWhileKeepingGlobalOrderUnique() throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        let project = try ProjectStore.create(name: "Launch", colorTag: nil, in: context)
        let first = try ProjectStore.addStep(to: project, title: "First", weekNumber: 1, in: context)
        let second = try ProjectStore.addStep(to: project, title: "Second", weekNumber: 1, in: context)
        _ = try ProjectStore.addStep(to: project, title: "Later", weekNumber: 2, in: context)

        try ProjectStore.moveStep(second, by: -1, in: context)

        #expect(second.order < first.order)
        #expect(Set(project.steps.map(\.order)).count == project.steps.count)
    }

    @Test func projectEditAppliesRenameReorderAndDeletionTogether() throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        let project = try ProjectStore.create(name: "Draft", colorTag: "garnet", in: context)
        let first = try ProjectStore.addStep(to: project, title: "First", weekNumber: 1, in: context)
        let second = try ProjectStore.addStep(to: project, title: "Second", weekNumber: 1, in: context)
        let removed = try ProjectStore.addStep(to: project, title: "Remove me", weekNumber: 2, in: context)

        try ProjectStore.applyEdits(
            to: project,
            name: "Final",
            colorTag: "forest",
            orderedSteps: [
                ProjectStepEdit(id: second.id, title: "Second edited", weekNumber: 1),
                ProjectStepEdit(id: first.id, title: "First", weekNumber: 1)
            ],
            in: context
        )

        #expect(project.name == "Final")
        #expect(project.colorTag == "forest")
        #expect(project.steps.sorted { $0.order < $1.order }.map(\.title) == ["Second edited", "First"])
        #expect(try context.fetch(FetchDescriptor<ProjectStep>()).contains { $0.id == removed.id } == false)
    }

    @Test func deletingEveryStepReturnsProjectToManualCompletionMode() throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        let project = try ProjectStore.create(name: "Draft", colorTag: nil, in: context)
        _ = try ProjectStore.addStep(to: project, title: "Only", weekNumber: 1, in: context)

        try ProjectStore.applyEdits(
            to: project,
            name: project.name,
            colorTag: project.colorTag,
            orderedSteps: [],
            in: context
        )

        #expect(project.steps.isEmpty)
        #expect(!project.isCompleted)
    }

    @Test func completedProjectCanBePermanentlyDeletedWithItsSteps() throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        let project = try ProjectStore.create(name: "Finished", colorTag: nil, in: context)
        let step = try ProjectStore.addStep(to: project, title: "Ship", weekNumber: 1, in: context)
        try ProjectCompletionStore.complete(step, in: context)

        try ProjectStore.delete(project, in: context)

        #expect(try context.fetch(FetchDescriptor<NightProject>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<ProjectStep>()).isEmpty)
    }
}
