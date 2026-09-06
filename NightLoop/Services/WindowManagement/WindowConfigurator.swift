import AppKit
import SwiftUI

struct WindowConfigurator: NSViewRepresentable {
    let floatsAboveOtherWindows: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.level = floatsAboveOtherWindows ? .floating : .normal
        window.minSize = NSSize(width: 380, height: 520)
        window.maxSize = NSSize(width: 560, height: CGFloat.greatestFiniteMagnitude)
        window.collectionBehavior.insert(.fullScreenAuxiliary)
        window.ignoresMouseEvents = false
        window.setFrameAutosaveName("NightLoopMainWindow")
    }
}
