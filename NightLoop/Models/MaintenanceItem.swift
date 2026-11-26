import Foundation
import SwiftData

enum MaintenanceKind: String, CaseIterable, Identifiable {
    case chores, doctorVisits

    var id: String { rawValue }
    var title: String { self == .chores ? "House Chores" : "Doctor Visits" }
    var iconName: String { self == .chores ? "house" : "stethoscope" }
    var itemName: String { self == .chores ? "Chore" : "Doctor" }
    var recordAction: String { self == .chores ? "Record Completion" : "Record Visit" }
    var frequencies: [MaintenanceFrequency] {
        MaintenanceFrequency.allCases.filter { self == .chores || $0 != .weekly }
    }
}

enum MaintenanceFrequency: String, CaseIterable, Identifiable {
    case weekly, monthly, quarterly, semiannual, yearly

    var id: String { rawValue }
    var title: String {
        switch self {
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .quarterly: "Every 3 Months"
        case .semiannual: "Every 6 Months"
        case .yearly: "Yearly"
        }
    }
}

extension NightLoopSchemaV7 {
    @Model final class MaintenanceItem {
        @Attribute(.unique) var id: UUID
        var title: String
        var kind: String
        var frequency: String
        var weekday: Int?
        @Relationship(deleteRule: .cascade, inverse: \MaintenanceRecord.item)
        var records: [MaintenanceRecord]

        init(id: UUID = UUID(), title: String, kind: MaintenanceKind, frequency: MaintenanceFrequency, weekday: Int? = nil) {
            self.id = id
            self.title = title
            self.kind = kind.rawValue
            self.frequency = frequency.rawValue
            self.weekday = weekday
            self.records = []
        }
    }

    @Model final class MaintenanceRecord {
        @Attribute(.unique) var id: UUID
        var date: Date
        var item: MaintenanceItem?

        init(id: UUID = UUID(), date: Date, item: MaintenanceItem) {
            self.id = id
            self.date = date
            self.item = item
        }
    }
}

typealias MaintenanceItem = NightLoopSchemaV7.MaintenanceItem
typealias MaintenanceRecord = NightLoopSchemaV7.MaintenanceRecord

extension MaintenanceItem {
    var lastRecordedDate: Date? { records.map(\.date).max() }

    func elapsedText(on date: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        guard let last = lastRecordedDate else { return "No date recorded" }
        let components = calendar.dateComponents([.year, .month, .day], from: calendar.startOfDay(for: last), to: calendar.startOfDay(for: date))
        let years = components.year ?? 0
        let months = components.month ?? 0
        let days = components.day ?? 0
        if years > 0 { return "\(years) year\(years == 1 ? "" : "s") ago" }
        if months > 0 { return "\(months) month\(months == 1 ? "" : "s") ago" }
        if days >= 7 { return "\(days / 7) week\(days / 7 == 1 ? "" : "s") ago" }
        if days > 0 { return "\(days) day\(days == 1 ? "" : "s") ago" }
        return "Today"
    }

    func isRecorded(on date: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        records.contains { calendar.isDate($0.date, inSameDayAs: date) }
    }

    func isRecordedThisWeek(on date: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        guard let range = calendar.weekRange(containing: date) else { return false }
        return records.contains { range.contains($0.date) }
    }
}
