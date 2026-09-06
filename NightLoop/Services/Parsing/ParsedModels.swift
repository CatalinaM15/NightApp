import Foundation

struct ParsedProject: Equatable, Sendable {
    var name: String
    var steps: [ParsedStep]
}

struct ParsedStep: Identifiable, Equatable, Sendable {
    let id: UUID
    var title: String
    var weekNumber: Int
    var order: Int
    let sourceLine: Int?

    init(
        id: UUID = UUID(),
        title: String,
        weekNumber: Int,
        order: Int,
        sourceLine: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.weekNumber = weekNumber
        self.order = order
        self.sourceLine = sourceLine
    }
}

enum ParserDiagnosticSeverity: String, Sendable {
    case error
    case notice
}

struct ParserDiagnostic: Identifiable, Equatable, Sendable {
    let severity: ParserDiagnosticSeverity
    let line: Int
    let source: String
    let message: String

    var id: String { "\(severity.rawValue)-\(line)-\(message)" }
}

struct QuickAddParseResult: Equatable, Sendable {
    var project: ParsedProject
    var diagnostics: [ParserDiagnostic]

    var errors: [ParserDiagnostic] { diagnostics.filter { $0.severity == .error } }
    var notices: [ParserDiagnostic] { diagnostics.filter { $0.severity == .notice } }
    var canPreview: Bool { !project.name.isEmpty && errors.isEmpty }
}

struct PreviewValidationIssue: Identifiable, Equatable, Sendable {
    let message: String
    var id: String { message }
}
