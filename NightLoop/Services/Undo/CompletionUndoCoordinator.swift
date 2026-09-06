import Foundation

@MainActor
final class CompletionUndoCoordinator: ObservableObject {
    @Published private(set) var message: String?
    private var action: (() -> Void)?
    private var expiryTask: Task<Void, Never>?
    private let expiry: Duration

    init(expiry: Duration = .seconds(5)) {
        self.expiry = expiry
    }

    func offer(message: String, action: @escaping () -> Void) {
        expiryTask?.cancel()
        self.message = message
        self.action = action
        let delay = expiry
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.clear()
        }
    }

    func undo() {
        let pendingAction = action
        clear()
        pendingAction?()
    }

    func clear() {
        expiryTask?.cancel()
        expiryTask = nil
        action = nil
        message = nil
    }
}
