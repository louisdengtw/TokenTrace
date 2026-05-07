import AppKit
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: "dev.louisdeng.tokentrace", category: "AppDelegate")

    private var usageManager: UsageManager!
    private var statusItemController: StatusItemController!
    private var mainWindowController: MainWindowController!
    private var notificationCoordinator: NotificationCoordinator!

    /// Set true by paths that should bypass the Quit intercept (status item Quit).
    /// Read by `applicationShouldTerminate(_:)`.
    private var userInitiatedQuit: Bool = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = MainMenuBuilder.build(target: self)

        let store: UsageStore
        do {
            let url = try UsageStore.defaultDatabaseURL()
            store = try UsageStore(url: url)
        } catch {
            log.error("UsageStore init failed: \(String(describing: error), privacy: .public)")
            // Surface a fatal-error dialog and bail; without persistence we can't run the dashboard.
            let alert = NSAlert()
            alert.messageText = "Could not open usage database"
            alert.informativeText = String(describing: error)
            alert.alertStyle = .critical
            alert.runModal()
            // Fatal init failure is one of the few real-quit paths.
            requestRealQuit()
            return
        }

        let manager = UsageManager(store: store)
        self.usageManager = manager

        self.notificationCoordinator = NotificationCoordinator()
        manager.onThresholdCrossed = { [weak self] threshold in
            self?.notificationCoordinator.deliverThresholdCrossed(threshold)
        }

        self.mainWindowController = MainWindowController(usageManager: manager)
        self.statusItemController = StatusItemController(
            usageManager: manager,
            openMainWindow: { [weak self] tab in
                self?.mainWindowController.show(initialTab: tab)
            }
        )
        statusItemController.install()

        manager.start()

        // Stats / Bartender / Ice convention:
        //   - user-initiated launch (Finder double-click, `open`, Spotlight) → show main window
        //   - SMAppService login-item auto-launch                             → menu bar only
        // Default to false (no window) when the key is absent: safer than surprising
        // the user with a window from a non-default launch path.
        let isUserLaunch = (notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool) ?? false
        if isUserLaunch {
            mainWindowController.show(initialTab: .dashboard)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Fires when the user `open`s an already-running instance, or clicks the Dock
        // icon while one is visible. Either way, surface the main window.
        mainWindowController.show(initialTab: .dashboard)
        return true
    }

    /// Intercepts ⌘Q / app menu Quit; routes them to "close all windows" while
    /// keeping the process alive. Status item right-click → Quit sets the
    /// `userInitiatedQuit` flag first to opt out of the intercept.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if userInitiatedQuit {
            return .terminateNow
        }

        // Close any visible windows. Stop polling so the popover doesn't re-appear data
        // mid-quit if the user keeps spamming ⌘Q. Polling will be re-attached when a
        // window opens again? — no, we want polling to keep running in the background.
        // So leave usageManager alone and only close windows.
        for window in NSApp.windows where window.isVisible && window.canBecomeMain {
            window.performClose(nil)
        }

        return .terminateCancel
    }

    /// Don't auto-quit when the last window closes — the menu bar item should
    /// keep the process alive in the background. Real quit is reachable via the
    /// status item right-click → Quit (which sets `userInitiatedQuit`).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        usageManager?.stop()
    }

    // MARK: - Menu actions

    /// Opens the main window with the Settings tab active. Wired to the
    /// Application menu's Settings… item (⌘,).
    @objc func openSettings(_ sender: Any?) {
        mainWindowController.show(initialTab: .settings)
    }

    /// Posts a notification that `MainWindowContent` listens for to toggle
    /// the sidebar collapse state. Wired to the View menu's Toggle Sidebar
    /// item (⌃⌘S).
    @objc func toggleSidebarAction(_ sender: Any?) {
        NotificationCenter.default.post(name: .toggleSidebar, object: nil)
    }

    // MARK: - Quit semantics

    /// Sets the `userInitiatedQuit` flag and calls `NSApp.terminate(_:)`.
    /// The flag is read by `applicationShouldTerminate(_:)`, so this path
    /// terminates the process for real, while ⌘Q / app menu Quit / programmatic
    /// `terminate(_:)` calls without prior consent are intercepted into "close
    /// all windows" instead.
    func requestRealQuit() {
        userInitiatedQuit = true
        NSApp.terminate(nil)
    }
}
