import AppKit
import SwiftUI

enum MainTab: Hashable {
    case menuBarPreview
    case dashboard
    case settings
}

@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    private let usageManager: UsageManager
    private var window: NSWindow?
    private var hostingController: NSHostingController<MainWindowContent>?
    private let selection = MainTabSelection()

    init(usageManager: UsageManager) {
        self.usageManager = usageManager
        super.init()
    }

    func show(initialTab: MainTab = .dashboard) {
        selection.selected = initialTab

        if let existing = window {
            activateForRegularPolicy()
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let content = MainWindowContent(usageManager: usageManager, selection: selection)
        let hosting = NSHostingController(rootView: content)
        self.hostingController = hosting

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "ClaudeUsage"
        window.contentViewController = hosting
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        self.window = window

        activateForRegularPolicy()
        window.makeKeyAndOrderFront(nil)
    }

    private func activateForRegularPolicy() {
        NSApp.setActivationPolicy(.regular)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, closing === window else { return }
        window = nil
        hostingController = nil
        NSApp.setActivationPolicy(.accessory)
    }
}

/// Lightweight observable used to drive `TabView` selection from outside SwiftUI.
@MainActor
final class MainTabSelection: ObservableObject {
    @Published var selected: MainTab = .dashboard
}
