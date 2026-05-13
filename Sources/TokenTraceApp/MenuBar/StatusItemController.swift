import AppKit
import Combine
import OSLog
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private let usageManager: UsageManager
    private let openMainWindow: (MainTab) -> Void
    private let log = Logger(subsystem: "dev.louisdeng.tokentrace", category: "StatusItem")

    private var statusItem: NSStatusItem?
    private var panel: MenuBarPanel?
    private var hostingController: NSHostingController<PopoverView>?
    private var globalClickMonitor: Any?
    private var localKeyMonitor: Any?
    private var cancellables: Set<AnyCancellable> = []

    init(usageManager: UsageManager, openMainWindow: @escaping (MainTab) -> Void) {
        self.usageManager = usageManager
        self.openMainWindow = openMainWindow
        super.init()
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        if let button = item.button {
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageOnly
        }

        installPanel()
        renderIcon()

        usageManager.$latestSample
            .combineLatest(usageManager.$hasFetchedData, usageManager.$sessionExpired)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _ in
                self?.renderIcon()
            }
            .store(in: &cancellables)

        // System appearance changes (light <-> dark) should re-render the icon
        // since we bake the colors into the rendered NSImage.
        DistributedNotificationCenter.default.addObserver(
            self,
            selector: #selector(appearanceChanged),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )
    }

    func togglePopover() {
        guard let panel else { return }
        if panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let button = statusItem?.button else { return }
        guard let buttonWindow = button.window else { return }
        guard let panel else { return }

        // Resize panel to the SwiftUI content's intrinsic size (popover lays
        // out vertically with no Spacer, so this captures the true height).
        hostingController?.view.layoutSubtreeIfNeeded()
        let fittingSize = hostingController?.view.fittingSize ?? NSSize(width: 320, height: 240)
        let panelSize = NSSize(
            width: max(fittingSize.width, 320),
            height: max(fittingSize.height, 200)
        )

        // Anchor below the status item button, on its screen. The small
        // vertical gap mirrors macOS's own menu-extra panels.
        let buttonFrameInWindow = button.convert(button.bounds, to: nil)
        let buttonFrameOnScreen = buttonWindow.convertToScreen(buttonFrameInWindow)
        let originX = buttonFrameOnScreen.midX - panelSize.width / 2
        let originY = buttonFrameOnScreen.minY - panelSize.height - 5
        panel.setContentSize(panelSize)
        panel.setFrameOrigin(NSPoint(x: originX, y: originY))

        panel.makeKeyAndOrderFront(nil)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }

        installDismissMonitors()
    }

    private func hidePanel() {
        panel?.orderOut(nil)
        removeDismissMonitors()
    }

    /// Outside-click and ESC-key handling. Global monitor catches clicks
    /// outside the panel (other apps, desktop, menu bar); local monitor
    /// handles ESC inside the panel itself.
    private func installDismissMonitors() {
        removeDismissMonitors()
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.hidePanel() }
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {  // ESC
                Task { @MainActor in self?.hidePanel() }
                return nil
            }
            return event
        }
    }

    private func removeDismissMonitors() {
        if let token = globalClickMonitor {
            NSEvent.removeMonitor(token)
            globalClickMonitor = nil
        }
        if let token = localKeyMonitor {
            NSEvent.removeMonitor(token)
            localKeyMonitor = nil
        }
    }

    // MARK: - Click handling

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showContextMenu(from: sender)
        } else {
            togglePopover()
        }
    }

    private func showContextMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Main Window", action: #selector(openMainWindowAction), keyEquivalent: "")
            .target = self

        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit TokenTrace", action: #selector(quitAction), keyEquivalent: "")
            .target = self

        statusItem?.menu = menu
        button.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func openMainWindowAction() {
        openMainWindow(.dashboard)
    }

    @objc private func quitAction() {
        // Real quit path. AppDelegate.requestRealQuit() flips the
        // userInitiatedQuit flag before invoking terminate so
        // applicationShouldTerminate(_:) returns .terminateNow.
        (NSApp.delegate as? AppDelegate)?.requestRealQuit()
    }

    @objc private func appearanceChanged() {
        Task { @MainActor in
            renderIcon()
        }
    }

    // MARK: - Panel

    private func installPanel() {
        let hosting = NSHostingController(
            rootView: PopoverView(
                usageManager: usageManager,
                openMainWindow: { [weak self] tab in
                    self?.openMainWindow(tab)
                    self?.hidePanel()
                }
            )
        )
        // Intrinsic-content sizing: the hosting controller asks the SwiftUI
        // view for its preferred size on each layout. macOS 13+ API.
        if #available(macOS 13.0, *) {
            hosting.sizingOptions = .intrinsicContentSize
        }
        self.hostingController = hosting
        self.panel = MenuBarPanel(contentView: hosting.view)
    }

    // MARK: - Icon rendering

    private func renderIcon() {
        guard let button = statusItem?.button else { return }

        let scheme: ColorScheme = isDarkAppearance(for: button) ? .dark : .light
        let view = StatsIconView(
            fiveHour: usageManager.latestSample[.fiveHour]?.util,
            sevenDay: usageManager.latestSample[.sevenDay]?.util,
            sevenDaySonnet: usageManager.hasWeeklySonnet
                ? usageManager.latestSample[.sevenDaySonnet]?.util
                : nil,
            scheme: scheme
        )

        let renderer = ImageRenderer(content: view.fixedSize())
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0
        if let image = renderer.nsImage {
            // Not a template image — we render our own threshold colors.
            image.isTemplate = false
            button.image = image
            button.title = ""
        }
    }

    private func isDarkAppearance(for view: NSView) -> Bool {
        let appearance = view.effectiveAppearance
        let match = appearance.bestMatch(from: [.darkAqua, .vibrantDark, .aqua, .vibrantLight])
        return match == .darkAqua || match == .vibrantDark
    }
}
