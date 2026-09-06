import SwiftData
import SwiftUI

@main
struct NightLoopApp: App {
    private let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainerFactory.makeContainer()
        } catch {
            fatalError("Unable to create NightLoop's local data store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .defaultSize(width: 420, height: 760)
        .windowResizability(.contentMinSize)
        .modelContainer(modelContainer)
    }
}
