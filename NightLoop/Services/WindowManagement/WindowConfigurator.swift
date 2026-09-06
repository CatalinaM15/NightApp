import AppKit
import SwiftUI

struct WindowConfigurator: NSViewRepresentable {
    let floatsAboveOtherWindows: Bool
    let joinsAllSpaces: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window, coordinator: context.coordinator) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView.window, coordinator: context.coordinator) }
    }

    private func configure(_ window: NSWindow?, coordinator: Coordinator) {
        guard let window else { return }
        window.level = floatsAboveOtherWindows ? .floating : .normal
        window.minSize = NSSize(width: 380, height: 520)
        window.maxSize = NSSize(width: 560, height: CGFloat.greatestFiniteMagnitude)
        window.collectionBehavior.insert(.fullScreenAuxiliary)
        if joinsAllSpaces {
            window.collectionBehavior.insert(.canJoinAllSpaces)
        } else {
            window.collectionBehavior.remove(.canJoinAllSpaces)
        }
        window.ignoresMouseEvents = false
        if !coordinator.didRestoreFrame {
            window.setFrameUsingName(Self.frameAutosaveName)
            window.setFrameAutosaveName(Self.frameAutosaveName)
            coordinator.didRestoreFrame = true
        }
    }

    private static let frameAutosaveName = "NightLoopMainWindow"

    final class Coordinator {
        var didRestoreFrame = false
    }
}
