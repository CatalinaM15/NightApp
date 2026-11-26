import EventKit
import Foundation
import Testing
@testable import NightLoop

@MainActor
@Suite("Reminders Inbox")
struct ReminderInboxTests {
    private func defaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: "InboxTests-\(UUID().uuidString)")!
        defaults.set("inbox", forKey: "inboxReminderListID")
        return defaults
    }

    @Test func titleValidationRejectsBlankInputAndTrimsWhitespace() throws {
        #expect(throws: ReminderInboxError.self) {
            try ReminderDraft(title: " \n ", listID: "inbox").validatedTitle()
        }
        #expect(try ReminderDraft(title: "  Call dentist \n", listID: "inbox").validatedTitle() == "Call dentist")
    }

    @Test func missingListDoesNotFallBackAndReadOnlyListCannotBeWritten() async {
        let store = FakeReminderStore()
        let model = ReminderInboxViewModel(store: store, defaults: defaults())
        await model.refresh()
        #expect(model.canWrite)
        store.availableLists = [ReminderList(id: "other", title: "Other", account: "Local", isWritable: true)]
        await model.refresh()
        #expect(model.selectedListID == "inbox")
        #expect(model.selectedList == nil)
        #expect(model.reminders.isEmpty)
        #expect(!model.canWrite)
        model.selectedListID = "other"
        store.availableLists = [ReminderList(id: "other", title: "Other", account: "Local", isWritable: false)]
        await model.refresh()
        #expect(!model.canWrite)
    }

    @Test func failedSaveCanBeRetriedAndSuccessfulSaveIsNotRetriedForRefreshFailure() async {
        let store = FakeReminderStore()
        let model = ReminderInboxViewModel(store: store, defaults: defaults())
        let draft = ReminderDraft(title: "Call dentist", notes: "Ask for availability", listID: "inbox")
        store.failSave = true
        #expect(await model.save(draft) == false)
        #expect(model.errorMessage != nil)
        #expect(!model.isSaving)
        store.failSave = false
        store.failFetch = true
        #expect(await model.save(draft))
        #expect(store.savedDrafts.count == 1)
        #expect(store.savedDrafts.first?.notes == draft.notes)
        #expect(model.errorMessage != nil)
        #expect(!model.isSaving)
    }

    @Test func deniedAccessClearsVisibleRemindersAndFailedCompletionDoesNotRemoveThem() async {
        let store = FakeReminderStore()
        let model = ReminderInboxViewModel(store: store, defaults: defaults())
        await model.refresh()
        #expect(model.reminders.count == 1)
        store.failSave = true
        #expect(await model.setCompleted(true, identifier: "one") == false)
        #expect(model.reminders.count == 1)
        store.authorizationStatus = .denied
        await model.refresh()
        #expect(model.reminders.isEmpty)
        #expect(model.lists.isEmpty)
        #expect(!model.canWrite)
    }

    @Test func delayedResponseCannotReplaceNewlySelectedList() async {
        let store = FakeReminderStore()
        store.delayFetch = true
        store.availableLists.append(ReminderList(id: "other", title: "Other", account: "Local", isWritable: true))
        let model = ReminderInboxViewModel(store: store, defaults: defaults())
        let oldRequest = Task { await model.refresh() }
        while store.pendingFetch == nil { await Task.yield() }
        model.selectedListID = "other"
        store.delayFetch = false
        await model.refresh()
        #expect(model.reminders.first?.listID == "other")
        store.pendingFetch?.resume(returning: [store.reminder(in: "inbox")])
        store.pendingFetch = nil
        await oldRequest.value
        #expect(model.reminders.first?.listID == "other")
        #expect(!model.isLoading)
    }
}

@MainActor
private final class FakeReminderStore: ReminderInboxStore {
    var authorizationStatus: EKAuthorizationStatus = .fullAccess
    var availableLists = [ReminderList(id: "inbox", title: "Inbox", account: "Local", isWritable: true)]
    var failSave = false
    var failFetch = false
    var delayFetch = false
    var pendingFetch: CheckedContinuation<[InboxReminder], Never>?
    var savedDrafts: [ReminderDraft] = []

    func requestAccess() async throws {}
    func lists() -> [ReminderList] { availableLists }
    func reminder(in listID: String) -> InboxReminder {
        InboxReminder(id: "one", title: "Call dentist", notes: "", listID: listID, dueDate: nil)
    }
    func reminders(in listID: String) async throws -> [InboxReminder] {
        if failFetch { throw ReminderInboxError.fetchFailed }
        if delayFetch {
            return await withCheckedContinuation { pendingFetch = $0 }
        }
        return [reminder(in: listID)]
    }
    func save(_ draft: ReminderDraft, replacing identifier: String?) async throws {
        if failSave { throw ReminderInboxError.readOnlyList }
        savedDrafts.append(draft)
    }
    func setCompleted(_ completed: Bool, identifier: String) throws {
        if failSave { throw ReminderInboxError.readOnlyList }
    }
}
