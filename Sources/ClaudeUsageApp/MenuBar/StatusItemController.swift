import AppKit
import Combine
import OSLog
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private let usageManager: UsageManager
    private let openMainWindow: (MainTab) -> Void
    private let log = Logger(subsystem: "dev.louisdeng.claudeusage", category: "StatusItem")

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
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

        installPopover()
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
        guard let button = statusItem?.button else { return }
        guard let popover else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            if #available(macOS 14.0, *) {
                NSApp.activate()
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
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
        menu.addItem(withTitle: "Quit ClaudeUsage", action: #selector(quitAction), keyEquivalent: "")
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

    // MARK: - Popover

    private func installPopover() {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 320, height: 280)
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(
                usageManager: usageManager,
                openMainWindow: { [weak self] tab in
                    self?.openMainWindow(tab)
                    self?.popover?.performClose(nil)
                }
            )
        )
        self.popover = popover
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
