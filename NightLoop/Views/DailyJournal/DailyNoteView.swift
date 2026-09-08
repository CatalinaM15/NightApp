import SwiftData
import SwiftUI

struct DailyNoteView: View {
    @Environment(\.modelContext) private var modelContext
    let date: Date
    let clearRevision: Int
    @Binding var hasText: Bool
    @ObservedObject var undoCoordinator: CompletionUndoCoordinator

    @State private var text = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: Binding(
                get: { text },
                set: { updateText($0) }
            ))
            .font(.body)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            if let errorMessage {
                Text(errorMessage).font(.caption2).foregroundStyle(.red)
            }
        }
        .task(id: CivilDay(date: date).key) { load() }
        .onChange(of: clearRevision) { _, _ in clear() }
    }

    private func load() {
        do {
            text = try DailyNoteStore.text(on: date, in: modelContext)
            hasText = !text.isEmpty
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updateText(_ updated: String) {
        text = updated
        hasText = !updated.isEmpty
        do {
            try DailyNoteStore.setText(updated, on: date, in: modelContext)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func clear() {
        guard !text.isEmpty else { return }
        let clearedText = text
        let clearedDate = date
        updateText("")
        guard errorMessage == nil else { return }
        undoCoordinator.offer(message: "Cleared note") {
            do {
                try DailyNoteStore.setText(clearedText, on: clearedDate, in: modelContext)
                if Calendar.autoupdatingCurrent.isDate(clearedDate, inSameDayAs: date) {
                    text = clearedText
                    hasText = true
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
