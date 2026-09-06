import SwiftData
import SwiftUI

struct QuickAddSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var existingProjects: [NightProject]

    let didImport: (NightProject) -> Void

    @State private var rawText = ""
    @State private var parseResult: QuickAddParseResult?
    @State private var draft: ParsedProject?
    @State private var importError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Quick Add Project").font(.title2.weight(.semibold))
                    Text(draft == nil ? "Paste a weekly plan." : "Review before saving.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }

            if draft == nil {
                inputView
            } else {
                previewView
            }
        }
        .padding(22)
        .frame(minWidth: 540, minHeight: 590)
    }

    private var inputView: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $rawText)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                if rawText.isEmpty {
                    Text("Project Name\nWeek 1\n- Step: First step\n- Step: Second step")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(13)
                        .allowsHitTesting(false)
                }
            }
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator))

            HStack {
                Text("\(rawText.count) / \(QuickAddParser.maximumCharacterCount)")
                    .font(.caption)
                    .foregroundStyle(rawText.count > QuickAddParser.maximumCharacterCount ? .red : .secondary)
                Spacer()
                Button("Preview") { parseInput() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let parseResult, !parseResult.diagnostics.isEmpty {
                diagnosticsView(parseResult.diagnostics)
            }
        }
    }

    private var previewView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let notices = parseResult?.notices, !notices.isEmpty {
                diagnosticsView(notices)
            }

            if let draftBinding = draftBinding {
                TextField("Project name", text: draftBinding.name)
                    .textFieldStyle(.roundedBorder)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(1...4, id: \.self) { week in
                            if draftBinding.wrappedValue.steps.contains(where: { $0.weekNumber == week }) {
                                VStack(alignment: .leading, spacing: 7) {
                                    Text("Week \(week)")
                                        .font(.headline)
                                    ForEach(draftBinding.wrappedValue.steps.filter { $0.weekNumber == week }) { step in
                                        if let binding = stepBinding(step.id) {
                                            QuickAddPreviewStepRow(
                                                step: binding,
                                                moveUp: { move(step.id, by: -1) },
                                                moveDown: { move(step.id, by: 1) },
                                                remove: { remove(step.id) }
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 330)

                if !validationIssues.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(validationIssues) { issue in
                            Label(issue.message, systemImage: "exclamationmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
                if let importError {
                    Text(importError).font(.caption).foregroundStyle(.red)
                }

                HStack {
                    Button("Back to Text") { draft = nil }
                    Spacer()
                    Button("Save Project") { saveProject() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!validationIssues.isEmpty)
                }
            }
        }
    }

    private var draftBinding: Binding<ParsedProject>? {
        guard draft != nil else { return nil }
        return Binding(
            get: { draft ?? ParsedProject(name: "", steps: []) },
            set: { draft = $0 }
        )
    }

    private var validationIssues: [PreviewValidationIssue] {
        guard let draft else { return [] }
        return QuickAddValidator.validate(draft, existingProjectNames: existingProjects.map(\.name))
    }

    private func stepBinding(_ id: UUID) -> Binding<ParsedStep>? {
        guard draft?.steps.contains(where: { $0.id == id }) == true else { return nil }
        return Binding(
            get: { draft!.steps.first(where: { $0.id == id })! },
            set: { updated in
                guard let index = draft?.steps.firstIndex(where: { $0.id == id }) else { return }
                draft?.steps[index] = updated
                normalizeOrder()
            }
        )
    }

    private func parseInput() {
        let result = QuickAddParser.parse(rawText)
        parseResult = result
        if result.canPreview { draft = result.project }
    }

    private func move(_ id: UUID, by offset: Int) {
        guard let source = draft?.steps.firstIndex(where: { $0.id == id }),
              let week = draft?.steps[source].weekNumber else { return }
        let weekIndices = draft!.steps.indices.filter { draft!.steps[$0].weekNumber == week }
        guard let position = weekIndices.firstIndex(of: source) else { return }
        let destinationPosition = position + offset
        guard weekIndices.indices.contains(destinationPosition) else { return }
        draft?.steps.swapAt(source, weekIndices[destinationPosition])
        normalizeOrder()
    }

    private func remove(_ id: UUID) {
        draft?.steps.removeAll { $0.id == id }
        normalizeOrder()
    }

    private func normalizeOrder() {
        guard var steps = draft?.steps else { return }
        steps.sort {
            if $0.weekNumber != $1.weekNumber { return $0.weekNumber < $1.weekNumber }
            return $0.order < $1.order
        }
        for index in steps.indices { steps[index].order = index }
        draft?.steps = steps
    }

    private func saveProject() {
        guard let draft, validationIssues.isEmpty else { return }
        do {
            let project = try ProjectImportService.save(draft, in: modelContext)
            didImport(project)
            dismiss()
        } catch {
            importError = error.localizedDescription
        }
    }

    private func diagnosticsView(_ diagnostics: [ParserDiagnostic]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(diagnostics) { diagnostic in
                    Label {
                        Text(diagnostic.line > 0
                             ? "Line \(diagnostic.line): \(diagnostic.message)"
                             : diagnostic.message)
                    } icon: {
                        Image(systemName: diagnostic.severity == .error
                              ? "exclamationmark.circle.fill"
                              : "wand.and.stars")
                    }
                    .font(.caption)
                    .foregroundStyle(diagnostic.severity == .error ? .red : .secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 110)
    }
}

private struct QuickAddPreviewStepRow: View {
    @Binding var step: ParsedStep
    let moveUp: () -> Void
    let moveDown: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField("Step title", text: $step.title)
                .textFieldStyle(.roundedBorder)
            Picker("Week", selection: $step.weekNumber) {
                ForEach(1...4, id: \.self) { Text("W\($0)").tag($0) }
            }
            .labelsHidden()
            .frame(width: 65)
            Button("Move Up", systemImage: "chevron.up", action: moveUp)
                .labelStyle(.iconOnly)
            Button("Move Down", systemImage: "chevron.down", action: moveDown)
                .labelStyle(.iconOnly)
            Button("Remove", systemImage: "trash", role: .destructive, action: remove)
                .labelStyle(.iconOnly)
        }
    }
}
