# HomeBase

![HomeBase app icon](NightLoop/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png)

A compact macOS app for daily routines, calendars, reminders, home maintenance, and personal projects. Built with SwiftUI and SwiftData, with a warm journal-style interface.

## Features

### Daily

An expandable checklist organized into **Morning, Afternoon, and Night**.

- Schedule steps for every day or selected weekdays.
- Add optional weekday variations beneath a step’s title.
- Keep Exercise linked to the selected activity in Today’s Cards, with one shared completion state. Move the fixed Exercise step between groups or reorder it.
- See Body Care activities and today’s weekly chores alongside your routine.
- Complete linked chores from Daily or the House Chores page; both use the same history.

### Today and Week

Daily and weekly agendas share a **60/40 split card** with scrollable event lists.

- Connect Calendar once for both columns.
- Choose calendars independently for Today and Week, or include all calendars automatically.
- Preview tomorrow by clicking the Today title. Daily and Inbox remain independent of that preview.
- See calendar colors, all-day events, and multi-day events. Canceled events and declined invitations are excluded.

### Today’s Cards and statistics

Choose Body Care, Exercise, and Hobby activities, assign weekday defaults, and track completion. Three Experiment slots support grouped checklists and archived experiment summaries. Weekly statistics summarize activity and routine completion.

### Reminders Inbox

Choose an existing Apple Reminders list to view, add, edit, move, and complete reminders. The compact list shows up to three rows before scrolling. Previous local notes remain available for copying into Inbox.

### House Chores and Doctor Visits

Open these pages using the house and stethoscope buttons beside Statistics.

- **Chores:** a weekday schedule, followed by Monthly, Every 3 Months, Every 6 Months, and Yearly sections.
- **Doctor visits:** the same longer frequency sections, without weekly scheduling.
- Record completions or visits, enter past dates, review history, and correct recorded dates.
- See how long it has been since the latest completion or visit.

### Projects and window settings

Manage projects with ordered weekly steps, completion tracking, and Quick Add import. Settings include keeping the window on top, showing it across desktop Spaces, and an optional nightly notification. Window size and position are remembered.

## Batch entry

In **Add Chore** or **Add Doctor**, enable **Batch add**. Use day or frequency headings, then one entry per line. The preview shows each assignment before the batch is saved.

```text
Monday:
Laundry
Change bedding

Tuesday:
Clean bathroom

Monthly:
Clean oven

Every 3 Months:
Clean windows

Every 6 Months:
Clean curtains

Yearly:
Review home maintenance
```

Doctor batches start with all four supported frequency headings ready to fill in:

```text
Monthly:
Monthly review

Every 3 Months:
Quarterly review

Every 6 Months:
Dentist

Yearly:
Vision
```

Blank lines are ignored. Headings apply until the next heading; entries before any heading use the form’s default frequency and day. Weekly headings are supported only for chores. An optional last-completion or last-visit date applies to every entry in that batch.

## Project Quick Add

Put the project name first, followed by consecutive week headings and step lines:

```text
Organize the kitchen
Week 1
- Step: Sort the pantry
- Step: List missing supplies
Week 2
- Step: Organize storage containers
```

Projects support up to four consecutive weeks and twelve steps. Quick Add accepts up to 10,000 characters and previews validation issues before importing.

## Requirements

- macOS 14 Sonoma or later.
- Xcode 16 or later for the project format and Swift Testing.
- Apple’s SwiftUI, SwiftData, EventKit, and UserNotifications frameworks. No external package dependencies are required.

The project, scheme, module, and bundle identifier retain the **NightLoop** name for compatibility with existing data. The built application is **HomeBase.app**.

## Build and run

1. Open `NightLoop.xcodeproj` in Xcode.
2. Select the **NightLoop** scheme and **My Mac** destination.
3. Configure your signing team if Xcode requests it.
4. Build and run with **Product → Run**.

To build a release from the repository root:

```bash
xcodebuild \
  -project NightLoop.xcodeproj \
  -scheme NightLoop \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/HomeBase-build \
  build
```

The application is generated at:

```text
/tmp/HomeBase-build/Build/Products/Release/HomeBase.app
```

Copy the built app into Applications to install it locally. Quit any development copy before opening the installed app.

## Permissions and storage

- **Calendar:** EventKit access is required to read events. HomeBase does not edit calendar events.
- **Reminders:** separate permission enables reading and writing the chosen list. Changes sync through the list’s existing account.
- **Notifications:** optional permission is requested when enabling the nightly reminder.

Routines, projects, maintenance entries, and their histories are stored locally with SwiftData. HomeBase does not use CloudKit for this local store or require its own backend account. Calendar and Reminders account synchronization remains managed by macOS and the account provider.

The sandboxed data store uses the existing bundle identifier, `com.nightloop.NightLoop`, and is located at:

```text
~/Library/Containers/com.nightloop.NightLoop/Data/Library/Application Support/NightLoopLocal.store
```

Schema migrations preserve data as the model evolves. Back up the app’s local data before replacing an installation or changing its persistence configuration.

## Tests

The `NightLoopTests` target uses Swift Testing for parsing, routine and project workflows, dates, calendar event handling, Inbox behavior, completion history, statistics, and schema migrations.

Run tests through **Product → Test** in Xcode, or from the repository root:

```bash
xcodebuild \
  -project NightLoop.xcodeproj \
  -scheme NightLoop \
  -destination 'platform=macOS' \
  test
```

The Xcode test target is app-hosted, so this command can launch HomeBase.

## Source layout

```text
Config/                 App metadata and sandbox entitlements
NightLoop/
  Components/           Shared visual styles and surfaces
  Models/               SwiftData models and versioned schemas
  Services/             Persistence, parsing, calendars, reminders, and statistics
  Views/                Dashboard, routines, maintenance, projects, and settings
NightLoopTests/         Automated tests
NightLoop.xcodeproj/    Xcode project and shared scheme
```
