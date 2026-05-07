import AppKit
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: "dev.louisdeng.claudeusage", category: "AppDelegate")

    private var usageManager: UsageManager!
    private var statusItemController: StatusItemController!
    private var mainWindowController: MainWindowController!
    private var notificationCoordinator: NotificationCoordinator!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

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
            NSApp.terminate(nil)
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

        // Best-effort: register hotkey if the user has previously enabled it.
        applyHotkeySetting()

        NotificationCenter.default.addObserver(
            forName: .hotkeySettingChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applyHotkeySetting()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        usageManager?.stop()
        HotKey.shared.unregister()
    }

    private func applyHotkeySetting() {
        if AppSettings.hotkeyEnabled {
            HotKey.shared.register { [weak self] in
                self?.statusItemController.togglePopover()
            }
        } else {
            HotKey.shared.unregister()
        }
    }
}
