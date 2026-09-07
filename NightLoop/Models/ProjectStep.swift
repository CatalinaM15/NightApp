import Foundation
import SwiftData

extension NightLoopSchemaV3 {
@Model final class ProjectStep {
    @Attribute(.unique) var id: UUID
    var title: String
    var order: Int
    var completedAt: Date?
    var weekNumber: Int
    var project: NightProject?

    init(
        id: UUID = UUID(),
        title: String,
        order: Int,
        completedAt: Date? = nil,
        weekNumber: Int,
        project: NightProject? = nil
    ) {
        self.id = id
        self.title = title
        self.order = order
        self.completedAt = completedAt
        self.weekNumber = weekNumber
        self.project = project
    }

    var isCompleted: Bool { completedAt != nil }
}
}

typealias ProjectStep = NightLoopSchemaV3.ProjectStep
