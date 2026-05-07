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
            button.imagePosition = .imageLeft
        }

        installPopover()
        applyState(latestFiveHour: nil, hasFetched: false, sessionExpired: usageManager.sessionExpired)

        // Re-render whenever the manager publishes new state.
        usageManager.$latestSample
            .combineLatest(usageManager.$hasFetchedData, usageManager.$sessionExpired)
            .receive(on: RunLoop.main)
            .sink { [weak self] sample, hasFetched, sessionExpired in
                self?.applyState(
                    latestFiveHour: sample[.fiveHour],
                    hasFetched: hasFetched,
                    sessionExpired: sessionExpired
                )
            }
            .store(in: &cancellables)
    }

    func togglePopover() {
        guard let button = statusItem?.button else { return }
        guard let popover else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Activate so popover keyboard input works.
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

        let toggleItem = NSMenuItem(
            title: "Toggle Usage",
            action: #selector(toggleUsageAction),
            keyEquivalent: "u"
        )
        toggleItem.keyEquivalentModifierMask = [.command]
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit ClaudeUsage", action: #selector(quitAction), keyEquivalent: "q")
            .target = self

        statusItem?.menu = menu
        button.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func openMainWindowAction() {
        openMainWindow(.dashboard)
    }

    @objc private func toggleUsageAction() {
        togglePopover()
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
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

    // MARK: - Rendering

    private func applyState(latestFiveHour: UsageSample?, hasFetched: Bool, sessionExpired: Bool) {
        guard let button = statusItem?.button else { return }

        let icon = NSImage(systemSymbolName: "chart.bar.xaxis", accessibilityDescription: "ClaudeUsage")
        icon?.isTemplate = false
        button.image = icon

        if sessionExpired {
            button.title = "  ⚠"
            button.contentTintColor = .systemOrange
            return
        }

        guard let sample = latestFiveHour, hasFetched else {
            button.title = ""
            button.contentTintColor = .secondaryLabelColor
            return
        }

        let pct = Int(sample.util.rounded())
        button.title = "  \(pct)%"
        button.contentTintColor = colorForUtilization(pct)
    }

    private func colorForUtilization(_ pct: Int) -> NSColor {
        switch pct {
        case ...50:    return .systemGreen
        case 51...75:  return .systemYellow
        case 76...90:  return .systemOrange
        default:       return .systemRed
        }
    }
}
