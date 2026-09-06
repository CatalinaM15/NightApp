import SwiftData
import Testing
@testable import NightLoop

struct QuickAddParserTests {
    @Test func parsesCanonicalPlan() throws {
        let result = QuickAddParser.parse("""
        Launch NightLoop
        Week 1
        - Step: Finish parser
        - Step: Review preview
        Week 2
        - Step: Ship build
        """)

        #expect(result.errors.isEmpty)
        #expect(result.project.name == "Launch NightLoop")
        #expect(result.project.steps.map(\.title) == ["Finish parser", "Review preview", "Ship build"])
        #expect(result.project.steps.map(\.weekNumber) == [1, 1, 2])
        #expect(result.project.steps.map(\.order) == [0, 1, 2])
    }

    @Test func acceptsAndReportsWeekNormalization() {
        let result = QuickAddParser.parse("""
        Launch
        Week 01:
        - Step: Prepare
        """)

        #expect(result.errors.isEmpty)
        #expect(result.project.steps.first?.weekNumber == 1)
        #expect(result.notices.contains { $0.line == 2 && $0.message.contains("Week 1") })
    }

    @Test func preservesOriginalLineNumbersAcrossBlankLines() {
        let result = QuickAddParser.parse("""
        Launch

        Week 1
        * Step: Wrong bullet
        """)

        #expect(result.errors.contains { $0.line == 4 })
    }

    @Test func rejectsStepsBeforeAWeekHeader() {
        let result = QuickAddParser.parse("""
        Launch
        - Step: Too early
        Week 1
        - Step: Valid
        """)

        #expect(result.errors.contains { $0.line == 2 && $0.message.contains("after a valid Week") })
    }

    @Test func rejectsDuplicateAndNonconsecutiveWeeks() {
        let duplicate = QuickAddParser.parse("""
        Launch
        Week 1
        - Step: First
        Week 1
        - Step: Duplicate block
        """)
        let gap = QuickAddParser.parse("""
        Launch
        Week 1
        - Step: First
        Week 3
        - Step: Gap
        """)

        #expect(duplicate.errors.contains { $0.message.contains("more than once") })
        #expect(gap.errors.contains { $0.message.contains("Expected Week 2") })
    }

    @Test func rejectsEmptyStepsAndWeeks() {
        let emptyStep = QuickAddParser.parse("""
        Launch
        Week 1
        - Step:
        """)
        let emptyWeek = QuickAddParser.parse("""
        Launch
        Week 1
        Week 2
        - Step: Work
        """)

        #expect(emptyStep.errors.contains { $0.message.contains("cannot be empty") })
        #expect(emptyWeek.errors.contains { $0.message.contains("at least one step") })
    }

    @Test func previewValidationFindsCapacityAndDuplicateErrors() {
        let project = ParsedProject(name: "Existing", steps: [
            ParsedStep(title: "Same", weekNumber: 1, order: 0),
            ParsedStep(title: "same", weekNumber: 1, order: 1),
            ParsedStep(title: "Third", weekNumber: 1, order: 2),
            ParsedStep(title: "Fourth", weekNumber: 1, order: 3)
        ])

        let issues = QuickAddValidator.validate(project, existingProjectNames: ["existing"])

        #expect(issues.contains { $0.message.contains("already exists") })
        #expect(issues.contains { $0.message.contains("three steps") })
        #expect(issues.contains { $0.message.contains("unique") })
    }

    @Test func enforcesInputCharacterLimit() {
        let result = QuickAddParser.parse(String(repeating: "x", count: 10_001))
        #expect(result.errors.contains { $0.message.contains("10,000") })
    }
}

@MainActor
struct ProjectImportServiceTests {
    @Test func importsPreviewWithOneSaveableObjectGraph() throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        let parsed = ParsedProject(name: "Imported", steps: [
            ParsedStep(title: "Second", weekNumber: 2, order: 1),
            ParsedStep(title: "First", weekNumber: 1, order: 0)
        ])

        let project = try ProjectImportService.save(parsed, in: context)

        #expect(project.name == "Imported")
        #expect(project.steps.count == 2)
        #expect(project.steps.sorted { $0.order < $1.order }.map(\.title) == ["First", "Second"])
        #expect(try context.fetch(FetchDescriptor<NightProject>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<ProjectStep>()).count == 2)
    }

    @Test func duplicateProjectImportDoesNotInsertAnything() throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        _ = try ProjectStore.create(name: "Imported", colorTag: nil, in: context)
        let parsed = ParsedProject(name: "imported", steps: [
            ParsedStep(title: "Work", weekNumber: 1, order: 0)
        ])

        #expect(throws: ProjectImportError.invalidPreview("A project with this name already exists.")) {
            try ProjectImportService.save(parsed, in: context)
        }
        #expect(try context.fetch(FetchDescriptor<NightProject>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<ProjectStep>()).isEmpty)
    }
}
