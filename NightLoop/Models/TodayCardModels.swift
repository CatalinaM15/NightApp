import Foundation
import SwiftData

enum RotatingCardCategory: String, CaseIterable, Identifiable {
    case bodyCare
    case exercise
    case hobby

    var id: String { rawValue }

    var slot: Int {
        switch self {
        case .bodyCare: 1
        case .exercise: 2
        case .hobby: 3
        }
    }

    var title: String {
        switch self {
        case .bodyCare: "Body Care"
        case .exercise: "Exercise"
        case .hobby: "Hobby"
        }
    }

    var iconName: String {
        switch self {
        case .bodyCare: "sparkles"
        case .exercise: "figure.run"
        case .hobby: "paintbrush.pointed"
        }
    }

    var initialOptions: [String] {
        switch self {
        case .bodyCare: ["Hair Wash", "Nail Care", "Shave", "Exfoliate"]
        case .exercise: ["Run", "Gym", "Class"]
        case .hobby: ["Read", "Paint", "Clay", "Code", "Other"]
        }
    }
}

extension NightLoopSchemaV4 {
@Model final class CardOption {
    @Attribute(.unique) var id: UUID
    var category: String
    var name: String
    var scheduledWeekdaysMask: Int
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        category: RotatingCardCategory,
        name: String,
        scheduledWeekdaysMask: Int = 0,
        sortOrder: Int
    ) {
        self.id = id
        self.category = category.rawValue
        self.name = name
        self.scheduledWeekdaysMask = scheduledWeekdaysMask
        self.sortOrder = sortOrder
    }
}

@Model final class SlotSelectionHistory {
    @Attribute(.unique) var id: UUID
    var category: String
    var optionName: String
    var date: Date
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        category: RotatingCardCategory,
        optionName: String,
        date: Date,
        completedAt: Date? = nil,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.id = id
        self.category = category.rawValue
        self.optionName = optionName
        self.date = calendar.startOfDay(for: date)
        self.completedAt = completedAt
    }
}

@Model final class ExperimentArchiveRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var totalActiveDays: Int
    var startDate: Date
    var endDate: Date
    var sourceSlot: Int

    init(
        id: UUID = UUID(),
        name: String,
        totalActiveDays: Int,
        startDate: Date,
        endDate: Date,
        sourceSlot: Int
    ) {
        self.id = id
        self.name = name
        self.totalActiveDays = totalActiveDays
        self.startDate = startDate
        self.endDate = endDate
        self.sourceSlot = sourceSlot
    }
}
}

typealias CardOption = NightLoopSchemaV4.CardOption
typealias SlotSelectionHistory = NightLoopSchemaV4.SlotSelectionHistory
typealias ExperimentArchiveRecord = NightLoopSchemaV4.ExperimentArchiveRecord
