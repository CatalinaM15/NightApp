import Foundation
import SwiftData

extension NightLoopSchemaV3 {
@Model final class NightProject {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var completedAt: Date?
    var colorTag: String?

    @Relationship(deleteRule: .cascade, inverse: \ProjectStep.project)
    var steps: [ProjectStep]

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = .now,
        completedAt: Date? = nil,
        colorTag: String? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.colorTag = colorTag
        self.steps = []
    }

    var isCompleted: Bool { completedAt != nil }
    var completedStepCount: Int { steps.lazy.filter(\.isCompleted).count }
}
}

typealias NightProject = NightLoopSchemaV3.NightProject
