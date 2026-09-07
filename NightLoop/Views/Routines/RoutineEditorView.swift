import SwiftUI

struct RoutineEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let initialTitle: String
    let initialIcon: String
    let allowsTypeSelection: Bool
    let save: (String, String, Int, Bool, [RoutineStepDraft]) throws -> Void

    @State private var routineTitle: String
    @State private var iconName: String
    @State private var scheduledWeekdaysMask: Int
    @State private var isGrouped: Bool
    @State private var stepDrafts: [RoutineStepDraft]
    @State private var errorMessage: String?

    private let icons = ["moon.stars", "paintbrush.pointed", "shower", "figure.run", "dumbbell", "camera", "video","sparkles"]

    init(
        title: String,
        initialTitle: String = "",
        initialIcon: String = "moon.stars",
        initialScheduledWeekdaysMask: Int = RoutineSchedule.allDaysMask,
        initialIsGrouped: Bool = false,
        initialSteps: [RoutineStepDraft] = [],
        allowsTypeSelection: Bool = true,
        save: @escaping (String, String, Int, Bool, [RoutineStepDraft]) throws -> Void
    ) {
        self.title = title
        self.initialTitle = initialTitle
        self.initialIcon = initialIcon
        self.allowsTypeSelection = allowsTypeSelection
        self.save = save
        _routineTitle = State(initialValue: initialTitle)
        _iconName = State(initialValue: initialIcon)
        _scheduledWeekdaysMask = State(initialValue: initialScheduledWeekdaysMask)
        _isGrouped = State(initialValue: initialIsGrouped)
        _stepDrafts = State(initialValue: initialSteps)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.title2.weight(.semibold))
            TextField("Routine name", text: $routineTitle)
                .textFieldStyle(.roundedBorder)

            if allowsTypeSelection {
                Toggle("Grouped routine", isOn: $isGrouped)
                    .onChange(of: isGrouped) { _, grouped in
                        if grouped && stepDrafts.isEmpty { stepDrafts = [RoutineStepDraft()] }
                    }
                Text("Grouped routines open a nightly checklist instead of completing immediately.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label(isGrouped ? "Grouped routine" : "Simple routine", systemImage: isGrouped ? "checklist" : "checkmark.circle")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Text("Icon")
                .font(.headline)
            HStack {
                ForEach(icons, id: \.self) { icon in
                    Button {
                        iconName = icon
                    } label: {
                        Image(systemName: icon)
                            .frame(width: 28, height: 28)
                            .background(iconName == icon ? JournalPalette.ember.opacity(0.22) : .clear, in: RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(icon)
                    .accessibilityValue(iconName == icon ? "Selected" : "Not selected")
                    .accessibilityAddTraits(iconName == icon ? .isSelected : [])
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Days")
                        .font(.headline)
                    Spacer()
                    Button(scheduledWeekdaysMask == RoutineSchedule.allDaysMask ? "Every day" : "Select all") {
                        scheduledWeekdaysMask = RoutineSchedule.allDaysMask
                    }
                    .buttonStyle(.link)
                    .disabled(scheduledWeekdaysMask == RoutineSchedule.allDaysMask)
                }

                HStack(spacing: 6) {
                    ForEach(RoutineWeekday.allCases) { weekday in
                        weekdayButton(weekday)
                    }
                }
                Text(scheduleSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if isGrouped {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Checklist Steps").font(.headline)
                        Spacer()
                        Button("Add Step", systemImage: "plus") {
                            stepDrafts.append(RoutineStepDraft())
                        }
                    }
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(stepDrafts) { draft in stepRow(draft) }
                        }
                    }
                    .frame(maxHeight: 190)
                    if stepDrafts.isEmpty {
                        Text("Add at least one step.").font(.caption).foregroundStyle(.red)
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { performSave() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(24)
        .frame(width: 470)
    }

    private func performSave() {
        do {
            try save(routineTitle, iconName, scheduledWeekdaysMask, isGrouped, isGrouped ? stepDrafts : [])
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var canSave: Bool {
        !routineTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        scheduledWeekdaysMask != 0 &&
        (!isGrouped || (!stepDrafts.isEmpty && stepDrafts.allSatisfy {
            !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }))
    }

    private func stepRow(_ draft: RoutineStepDraft) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal").foregroundStyle(.secondary).help("Drag to reorder")
            TextField("Step title", text: binding(for: draft.id).title).textFieldStyle(.roundedBorder)
            Button { stepDrafts.removeAll { $0.id == draft.id } } label: {
                Label("Delete Step", systemImage: "trash")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
        }
        .contentShape(Rectangle())
        .draggable(draft.id.uuidString)
        .dropDestination(for: String.self) { identifiers, _ in
            guard let value = identifiers.first, let sourceID = UUID(uuidString: value) else { return false }
            return move(sourceID, before: draft.id)
        }
    }

    private func binding(for id: UUID) -> Binding<RoutineStepDraft> {
        Binding(
            get: { stepDrafts.first(where: { $0.id == id }) ?? RoutineStepDraft(id: id) },
            set: { updated in
                guard let index = stepDrafts.firstIndex(where: { $0.id == id }) else { return }
                stepDrafts[index] = updated
            }
        )
    }

    private func move(_ sourceID: UUID, before targetID: UUID) -> Bool {
        guard sourceID != targetID,
              let source = stepDrafts.firstIndex(where: { $0.id == sourceID }),
              let target = stepDrafts.firstIndex(where: { $0.id == targetID }) else { return false }
        let moved = stepDrafts.remove(at: source)
        stepDrafts.insert(moved, at: min(target, stepDrafts.endIndex))
        return true
    }

    private func weekdayButton(_ weekday: RoutineWeekday) -> some View {
        let selected = RoutineSchedule.contains(weekday, in: scheduledWeekdaysMask)
        return Button {
            scheduledWeekdaysMask = RoutineSchedule.toggling(weekday, in: scheduledWeekdaysMask)
        } label: {
            Text(weekday.shortName)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 28)
                .background(selected ? JournalPalette.raised : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                .foregroundStyle(selected ? JournalPalette.ink : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(weekday.shortName)
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var scheduleSummary: String {
        let selected = RoutineWeekday.allCases.filter { RoutineSchedule.contains($0, in: scheduledWeekdaysMask) }
        if selected.isEmpty { return "Choose at least one day." }
        if selected.count == RoutineWeekday.allCases.count { return "Appears every day." }
        return "Appears on " + selected.map(\.shortName).joined(separator: ", ") + "."
    }
}
