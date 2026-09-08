import AppKit
import SwiftUI

/// A plain titled window hosting a SwiftUI view, reused by onboarding and the sleep report.
final class PanelWindow {
    private var window: NSWindow?

    func show<Content: View>(title: String, width: CGFloat, @ViewBuilder content: () -> Content) {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 100),
                             styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.title = title
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            window = w
        }
        window?.contentView = NSHostingView(rootView: content().frame(width: width))
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func close() { window?.close() }
}
