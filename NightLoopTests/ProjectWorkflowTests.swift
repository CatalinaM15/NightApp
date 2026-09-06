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
}
