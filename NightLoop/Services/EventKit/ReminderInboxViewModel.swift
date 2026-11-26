import EventKit
import Foundation

@MainActor
final class ReminderInboxViewModel: ObservableObject {
    @Published private(set) var authorizationStatus: EKAuthorizationStatus
    @Published private(set) var lists: [ReminderList] = []
    @Published private(set) var reminders: [InboxReminder] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var isConnecting = false
    @Published private(set) var errorMessage: String?
    @Published var selectedListID: String {
        didSet { defaults.set(selectedListID, forKey: "inboxReminderListID") }
    }

    private let store: any ReminderInboxStore
    private let defaults: UserDefaults
    private var refreshRevision = 0
    private var loadedListID: String?

    init(store: (any ReminderInboxStore)? = nil, defaults: UserDefaults = .standard) {
        let store = store ?? ReminderInboxService()
        self.store = store
        self.defaults = defaults
        self.authorizationStatus = store.authorizationStatus
        self.selectedListID = defaults.string(forKey: "inboxReminderListID") ?? ""
    }

    var selectedList: ReminderList? { lists.first { $0.id == selectedListID } }
    var canWrite: Bool { authorizationStatus == .fullAccess && selectedList?.isWritable == true }

    func connect() async {
        guard !isConnecting else { return }
        isConnecting = true
        defer { isConnecting = false }
        do {
            try await store.requestAccess()
            await refresh()
        } catch {
            authorizationStatus = store.authorizationStatus
            errorMessage = error.localizedDescription
        }
    }

    func refresh() async {
        refreshRevision += 1
        let revision = refreshRevision
        let listID = selectedListID
        if loadedListID != listID { reminders = [] }
        authorizationStatus = store.authorizationStatus
        errorMessage = nil
        guard authorizationStatus == .fullAccess else {
            lists = []
            reminders = []
            isLoading = false
            return
        }
        lists = store.lists()
        guard selectedList != nil else {
            reminders = []
            isLoading = false
            return
        }
        isLoading = true
        do {
            let fetched = try await store.reminders(in: listID)
            guard revision == refreshRevision, listID == selectedListID else { return }
            reminders = fetched
            loadedListID = listID
        } catch {
            guard revision == refreshRevision, listID == selectedListID else { return }
            reminders = []
            errorMessage = error.localizedDescription
        }
        if revision == refreshRevision { isLoading = false }
    }

    func save(_ draft: ReminderDraft, replacing identifier: String? = nil) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await store.save(draft, replacing: identifier)
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
        // Saving succeeded even if a subsequent refresh fails; don't offer a duplicate creation.
        await refresh()
        return true
    }

    func setCompleted(_ completed: Bool, identifier: String) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do { try store.setCompleted(completed, identifier: identifier) }
        catch {
            errorMessage = error.localizedDescription
            return false
        }
        await refresh()
        return true
    }
}
