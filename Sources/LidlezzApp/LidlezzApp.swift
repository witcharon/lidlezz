import AppKit
import Combine
import SwiftUI

@main
struct LidlezzApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

/// Status item plus a real NSPopover, which follows the SwiftUI content size as the panel grows and shrinks.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = Model()
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var titleUpdates: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        exitIfAlreadyRunning()
        NSApp.setActivationPolicy(.accessory)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = Brand.menuBar
        item.button?.imagePosition = .imageLeading
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        statusItem = item

        let host = NSHostingController(rootView: StatusPanel().environmentObject(model))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.behavior = .transient

        titleUpdates = model.$snap.sink { [weak self] snap in
            self?.statusItem?.button?.title = snap.guarding ? self?.model.menuTitle ?? "" : ""
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
            // Switches render gray in a window that is not key.
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    /// One menu bar item is enough.
    private func exitIfAlreadyRunning() {
        let me = Bundle.main.executableURL?.resolvingSymlinksInPath()
        let twin = NSWorkspace.shared.runningApplications.contains {
            $0.processIdentifier != getpid() && $0.executableURL?.resolvingSymlinksInPath() == me
        }
        if twin { exit(0) }
    }
}
