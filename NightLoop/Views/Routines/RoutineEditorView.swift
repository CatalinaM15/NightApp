import SwiftUI

struct RoutineEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let initialTitle: String
    let initialIcon: String
    let save: (String, String, Int) throws -> Void

    @State private var routineTitle: String
    @State private var iconName: String
    @State private var scheduledWeekdaysMask: Int
    @State private var errorMessage: String?

    private let icons = ["moon.stars", "book.closed", "figure.mind.and.body", "drop", "sparkles", "pencil"]

    init(
        title: String,
        initialTitle: String = "",
        initialIcon: String = "moon.stars",
        initialScheduledWeekdaysMask: Int = RoutineSchedule.allDaysMask,
        save: @escaping (String, String, Int) throws -> Void
    ) {
        self.title = title
        self.initialTitle = initialTitle
        self.initialIcon = initialIcon
        self.save = save
        _routineTitle = State(initialValue: initialTitle)
        _iconName = State(initialValue: initialIcon)
        _scheduledWeekdaysMask = State(initialValue: initialScheduledWeekdaysMask)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.title2.weight(.semibold))
            TextField("Routine name", text: $routineTitle)
                .textFieldStyle(.roundedBorder)

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
                    .disabled(routineTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || scheduledWeekdaysMask == 0)
            }
        }
        .padding(24)
        .frame(width: 390)
    }

    private func performSave() {
        do {
            try save(routineTitle, iconName, scheduledWeekdaysMask)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
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
