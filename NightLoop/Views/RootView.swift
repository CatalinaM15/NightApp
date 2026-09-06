import SwiftUI

struct RootView: View {
    @AppStorage("floatsAboveOtherWindows") private var floatsAboveOtherWindows = true
    @StateObject private var dayCoordinator = JournalDayCoordinator()
    @StateObject private var undoCoordinator = CompletionUndoCoordinator()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                WeeklyGlanceStrip(referenceDate: dayCoordinator.visibleDate)
                JournalSection(title: "Tomorrow", systemImage: "calendar") {
                    TomorrowEventsSection(
                        referenceDate: dayCoordinator.visibleDate,
                        refreshRevision: dayCoordinator.calendarRefreshRevision
                    )
                }
                JournalSection(title: "Evening Ritual", systemImage: "moon.stars") {
                    RoutineListView(
                        date: dayCoordinator.visibleDate,
                        undoCoordinator: undoCoordinator
                    )
                }
                JournalSection(title: "Projects", systemImage: "checklist") {
                    Text("Your active project steps will live here.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
        .frame(minWidth: 380, minHeight: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(WindowConfigurator(floatsAboveOtherWindows: floatsAboveOtherWindows))
        .overlay(alignment: .bottom) {
            if let message = undoCoordinator.message {
                UndoToast(message: message, undo: undoCoordinator.undo)
                    .padding()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: undoCoordinator.message)
        .toolbar {
            ToolbarItem {
                Toggle(isOn: $floatsAboveOtherWindows) {
                    Label("Keep on Top", systemImage: floatsAboveOtherWindows ? "pin.fill" : "pin")
                }
                .toggleStyle(.button)
                .help("Keep NightLoop above other windows")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("NightLoop")
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
            Text(dayCoordinator.visibleDate.formatted(date: .complete, time: .omitted))
                .foregroundStyle(.secondary)
        }
    }
}

private struct UndoToast: View {
    let message: String
    let undo: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Text(message)
                .lineLimit(1)
            Button("Undo", action: undo)
                .keyboardShortcut("z", modifiers: .command)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .shadow(radius: 8, y: 3)
        .accessibilityElement(children: .contain)
    }
}

private struct JournalSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.system(.title3, design: .rounded, weight: .semibold))
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
    }
}
