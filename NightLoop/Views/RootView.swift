import SwiftUI

struct RootView: View {
    @AppStorage("floatsAboveOtherWindows") private var floatsAboveOtherWindows = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                WeeklyGlanceStrip()
                JournalSection(title: "Tomorrow", systemImage: "calendar") {
                    ContentUnavailableView(
                        "Calendar Not Connected",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("Calendar access arrives in Milestone 3.")
                    )
                    .frame(maxWidth: .infinity)
                }
                JournalSection(title: "Evening Ritual", systemImage: "moon.stars") {
                    Text("Your routines will live here.")
                        .foregroundStyle(.secondary)
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
            Text(Date.now.formatted(date: .complete, time: .omitted))
                .foregroundStyle(.secondary)
        }
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
