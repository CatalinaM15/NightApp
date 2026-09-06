import Foundation

enum QuickAddParser {
    static let maximumCharacterCount = 10_000

    static func parse(_ rawText: String) -> QuickAddParseResult {
        guard rawText.count <= maximumCharacterCount else {
            return QuickAddParseResult(
                project: ParsedProject(name: "", steps: []),
                diagnostics: [ParserDiagnostic(
                    severity: .error,
                    line: 1,
                    source: "",
                    message: "Quick Add accepts up to 10,000 characters."
                )]
            )
        }

        let normalizedLineEndings = rawText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalizedLineEndings.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var projectName = ""
        var steps: [ParsedStep] = []
        var diagnostics: [ParserDiagnostic] = []
        var currentWeek: Int?
        var currentWeekLine: Int?
        var currentWeekStepCount = 0
        var seenWeeks: Set<Int> = []
        var expectedWeek = 1

        for (index, source) in lines.enumerated() {
            let lineNumber = index + 1
            let line = source.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            if projectName.isEmpty {
                projectName = line
                continue
            }

            if let weekText = capture(in: line, pattern: #"(?i)^Week\s+([0-9]+):?$"#),
               let week = Int(weekText) {
                if let previousLine = currentWeekLine, currentWeekStepCount == 0 {
                    diagnostics.append(error(
                        line: previousLine,
                        source: lines[previousLine - 1],
                        "Every week needs at least one step."
                    ))
                }
                currentWeek = week
                currentWeekLine = lineNumber
                currentWeekStepCount = 0

                if !(1...4).contains(week) {
                    diagnostics.append(error(line: lineNumber, source: source, "Week numbers must be from 1 through 4."))
                    continue
                }
                if seenWeeks.contains(week) {
                    diagnostics.append(error(line: lineNumber, source: source, "Week \(week) appears more than once."))
                } else {
                    seenWeeks.insert(week)
                }
                if week != expectedWeek {
                    diagnostics.append(error(
                        line: lineNumber,
                        source: source,
                        "Expected Week \(expectedWeek). Weeks must begin at 1 and be consecutive."
                    ))
                } else {
                    expectedWeek += 1
                }

                let canonical = "Week \(week)"
                if line != canonical {
                    diagnostics.append(notice(line: lineNumber, source: source, "Normalized to “\(canonical)”."))
                }
                continue
            }

            if let capturedTitle = capture(in: line, pattern: #"(?i)^-\s*Step:\s*(.*)$"#) {
                guard let week = currentWeek, (1...4).contains(week) else {
                    diagnostics.append(error(line: lineNumber, source: source, "A step must appear after a valid Week header."))
                    continue
                }
                let title = capturedTitle.trimmingCharacters(in: .whitespaces)
                guard !title.isEmpty else {
                    diagnostics.append(error(line: lineNumber, source: source, "A step title cannot be empty."))
                    continue
                }
                steps.append(ParsedStep(
                    title: title,
                    weekNumber: week,
                    order: steps.count,
                    sourceLine: lineNumber
                ))
                currentWeekStepCount += 1
                let canonical = "- Step: \(title)"
                if line != canonical {
                    diagnostics.append(notice(line: lineNumber, source: source, "Normalized step formatting."))
                }
                continue
            }

            diagnostics.append(error(
                line: lineNumber,
                source: source,
                "Use “Week 1” or “- Step: Description”."
            ))
        }

        if projectName.isEmpty {
            diagnostics.append(error(line: 1, source: "", "Enter a project name on the first non-empty line."))
        }
        if let previousLine = currentWeekLine, currentWeekStepCount == 0 {
            diagnostics.append(error(
                line: previousLine,
                source: lines[previousLine - 1],
                "Every week needs at least one step."
            ))
        }
        if steps.isEmpty {
            diagnostics.append(error(line: 0, source: "", "Quick Add requires at least one valid step."))
        }

        let project = ParsedProject(name: projectName, steps: steps)
        return QuickAddParseResult(project: project, diagnostics: unique(diagnostics))
    }

    private static func capture(in value: String, pattern: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: value,
                range: NSRange(value.startIndex..., in: value)
              ),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: value) else {
            return nil
        }
        return String(value[range])
    }

    private static func error(line: Int, source: String, _ message: String) -> ParserDiagnostic {
        ParserDiagnostic(severity: .error, line: line, source: source, message: message)
    }

    private static func notice(line: Int, source: String, _ message: String) -> ParserDiagnostic {
        ParserDiagnostic(severity: .notice, line: line, source: source, message: message)
    }

    private static func unique(_ diagnostics: [ParserDiagnostic]) -> [ParserDiagnostic] {
        var seen: Set<String> = []
        return diagnostics.filter { seen.insert($0.id).inserted }
    }
}

enum QuickAddValidator {
    static func validate(
        _ project: ParsedProject,
        existingProjectNames: [String]
    ) -> [PreviewValidationIssue] {
        var issues: [PreviewValidationIssue] = []
        let name = project.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            issues.append(PreviewValidationIssue(message: "The project needs a name."))
        } else if existingProjectNames.contains(where: {
            $0.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            issues.append(PreviewValidationIssue(message: "A project with this name already exists."))
        }

        if project.steps.isEmpty {
            issues.append(PreviewValidationIssue(message: "Quick Add requires at least one step."))
        }
        if project.steps.count > 12 {
            issues.append(PreviewValidationIssue(message: "A project can contain at most 12 steps."))
        }

        for step in project.steps {
            if step.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(PreviewValidationIssue(message: "Every step needs a title."))
                break
            }
            if !(1...4).contains(step.weekNumber) {
                issues.append(PreviewValidationIssue(message: "Every step must belong to Week 1 through Week 4."))
                break
            }
        }

        let grouped = Dictionary(grouping: project.steps, by: \.weekNumber)
        if grouped.values.contains(where: { $0.count > 3 }) {
            issues.append(PreviewValidationIssue(message: "Each week can contain at most three steps."))
        }
        let weeks = grouped.keys.filter { (1...4).contains($0) }.sorted()
        if !weeks.isEmpty && weeks != Array(1...weeks.count) {
            issues.append(PreviewValidationIssue(message: "Weeks must begin at Week 1 and remain consecutive."))
        }

        let normalizedTitles = project.steps.map {
            $0.title.trimmingCharacters(in: .whitespacesAndNewlines).folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
        }
        if Set(normalizedTitles).count != normalizedTitles.count {
            issues.append(PreviewValidationIssue(message: "Step titles must be unique within the project."))
        }
        return issues
    }
}
