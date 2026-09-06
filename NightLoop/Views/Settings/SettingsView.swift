import AppKit
import SwiftUI

struct SettingsView: View {
    @AppStorage("floatsAboveOtherWindows") private var floatsAboveOtherWindows = true
    @AppStorage("joinsAllSpaces") private var joinsAllSpaces = false
    @AppStorage("nightlyReminderEnabled") private var reminderEnabled = false
    @AppStorage("nightlyReminderHour") private var reminderHour = 21
    @AppStorage("nightlyReminderMinute") private var reminderMinute = 0

    @StateObject private var calendar = CalendarSettingsViewModel()
    @State private var reminderError: String?

    var body: some View {
        Form {
            Section("Window") {
                Toggle("Keep NightLoop above other windows", isOn: $floatsAboveOtherWindows)
                Toggle("Show on every desktop Space", isOn: $joinsAllSpaces)
                Text("NightLoop remembers the panel’s size and position automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Nightly Ritual Reminder") {
                Toggle("Remind me each evening", isOn: $reminderEnabled)
                DatePicker(
                    "Reminder time",
                    selection: reminderDate,
                    displayedComponents: .hourAndMinute
                )
                .disabled(!reminderEnabled)
                Text("The reminder is scheduled locally on this Mac. Nothing is uploaded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Calendar") {
                Label(calendar.statusDescription, systemImage: calendar.permissionState == .fullAccess ? "checkmark.circle.fill" : "calendar")
                    .foregroundStyle(calendar.permissionState == .fullAccess ? .green : .secondary)
                HStack {
                    if calendar.permissionState == .notDetermined {
                        Button("Connect Calendar") { Task { await calendar.connect() } }
                            .disabled(calendar.isRequesting)
                    } else if calendar.permissionState != .restricted {
                        Button("Open Calendar Privacy Settings") { calendar.openPrivacySettings() }
                    }
                    Button("Check Again") { calendar.refresh() }
                }
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .frame(width: 500, height: 430)
        .onChange(of: reminderEnabled) { _, enabled in updateReminder(enabled: enabled) }
        .onChange(of: reminderHour) { _, _ in updateReminder(enabled: reminderEnabled) }
        .onChange(of: reminderMinute) { _, _ in updateReminder(enabled: reminderEnabled) }
        .alert("Reminder Could Not Be Enabled", isPresented: Binding(
            get: { reminderError != nil },
            set: { if !$0 { reminderError = nil } }
        )) {
            Button("Open Notification Settings") { openNotificationSettings() }
            Button("OK", role: .cancel) {}
        } message: {
            Text(reminderError ?? "Please check Notification settings for NightLoop.")
        }
    }

    private var reminderDate: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(from: DateComponents(hour: reminderHour, minute: reminderMinute)) ?? .now
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                reminderHour = components.hour ?? 21
                reminderMinute = components.minute ?? 0
            }
        )
    }

    private func updateReminder(enabled: Bool) {
        let time = NightlyReminderTime(hour: reminderHour, minute: reminderMinute)
        Task {
            do {
                if enabled {
                    try await NightlyReminderScheduler.shared.enable(at: time)
                } else {
                    await NightlyReminderScheduler.shared.disable()
                }
            } catch {
                reminderEnabled = false
                reminderError = error.localizedDescription
            }
        }
    }

    private func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") else { return }
        NSWorkspace.shared.open(url)
    }
}
