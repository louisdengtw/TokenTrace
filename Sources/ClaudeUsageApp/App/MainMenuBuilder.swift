import AppKit

extension Notification.Name {
    /// Posted by the View menu's Toggle Sidebar item; observed in `MainWindowContent`.
    static let toggleSidebar = Notification.Name("dev.louisdeng.claudeusage.toggleSidebar")
}

@MainActor
enum MainMenuBuilder {
    /// Build the standard macOS menu bar. Hooks application-level items
    /// (Settings…, Toggle Sidebar) up to `AppDelegate` selectors.
    static func build(target: AppDelegate) -> NSMenu {
        let mainMenu = NSMenu()

        mainMenu.addItem(withSubmenu: buildApplicationMenu(target: target))
        mainMenu.addItem(withSubmenu: buildFileMenu())
        mainMenu.addItem(withSubmenu: buildEditMenu())
        mainMenu.addItem(withSubmenu: buildViewMenu(target: target))

        let windowMenu = buildWindowMenu()
        mainMenu.addItem(withSubmenu: windowMenu)
        NSApp.windowsMenu = windowMenu

        let helpMenu = buildHelpMenu()
        mainMenu.addItem(withSubmenu: helpMenu)
        NSApp.helpMenu = helpMenu

        return mainMenu
    }

    // MARK: - Application

    private static func buildApplicationMenu(target: AppDelegate) -> NSMenu {
        let menu = NSMenu(title: "ClaudeUsage")

        menu.addItem(withTitle: "About ClaudeUsage",
                     action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                     keyEquivalent: "")

        menu.addItem(.separator())

        let settings = NSMenuItem(
            title: "Settings…",
            action: #selector(AppDelegate.openSettings(_:)),
            keyEquivalent: ","
        )
        settings.target = target
        menu.addItem(settings)

        menu.addItem(.separator())

        let services = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "Services")
        services.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu
        menu.addItem(services)

        menu.addItem(.separator())

        menu.addItem(withTitle: "Hide ClaudeUsage",
                     action: #selector(NSApplication.hide(_:)),
                     keyEquivalent: "h")

        let hideOthers = NSMenuItem(
            title: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(hideOthers)

        menu.addItem(withTitle: "Show All",
                     action: #selector(NSApplication.unhideAllApplications(_:)),
                     keyEquivalent: "")

        menu.addItem(.separator())

        // Standard ⌘Q. Routed through `applicationShouldTerminate(_:)`,
        // which intercepts unless `userInitiatedQuit` is set.
        menu.addItem(withTitle: "Quit ClaudeUsage",
                     action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")

        return menu
    }

    // MARK: - File

    private static func buildFileMenu() -> NSMenu {
        let menu = NSMenu(title: "File")
        menu.addItem(withTitle: "Close",
                     action: #selector(NSWindow.performClose(_:)),
                     keyEquivalent: "w")
        return menu
    }

    // MARK: - Edit

    private static func buildEditMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")

        menu.addItem(withTitle: "Undo",
                     action: Selector(("undo:")),
                     keyEquivalent: "z")
        let redo = NSMenuItem(
            title: "Redo",
            action: Selector(("redo:")),
            keyEquivalent: "z"
        )
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(redo)

        menu.addItem(.separator())

        menu.addItem(withTitle: "Cut",
                     action: #selector(NSText.cut(_:)),
                     keyEquivalent: "x")
        menu.addItem(withTitle: "Copy",
                     action: #selector(NSText.copy(_:)),
                     keyEquivalent: "c")
        menu.addItem(withTitle: "Paste",
                     action: #selector(NSText.paste(_:)),
                     keyEquivalent: "v")

        menu.addItem(.separator())

        menu.addItem(withTitle: "Select All",
                     action: #selector(NSText.selectAll(_:)),
                     keyEquivalent: "a")

        return menu
    }

    // MARK: - View

    private static func buildViewMenu(target: AppDelegate) -> NSMenu {
        let menu = NSMenu(title: "View")

        let toggleSidebar = NSMenuItem(
            title: "Toggle Sidebar",
            action: #selector(AppDelegate.toggleSidebarAction(_:)),
            keyEquivalent: "s"
        )
        toggleSidebar.keyEquivalentModifierMask = [.command, .control]
        toggleSidebar.target = target
        menu.addItem(toggleSidebar)

        return menu
    }

    // MARK: - Window

    private static func buildWindowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(withTitle: "Minimize",
                     action: #selector(NSWindow.performMiniaturize(_:)),
                     keyEquivalent: "m")
        menu.addItem(withTitle: "Zoom",
                     action: #selector(NSWindow.performZoom(_:)),
                     keyEquivalent: "")
        return menu
    }

    // MARK: - Help

    private static func buildHelpMenu() -> NSMenu {
        let menu = NSMenu(title: "Help")
        let help = NSMenuItem(title: "ClaudeUsage Help", action: nil, keyEquivalent: "?")
        menu.addItem(help)
        return menu
    }
}

private extension NSMenu {
    /// Convenience: insert a submenu by wrapping it in a host `NSMenuItem`.
    func addItem(withSubmenu submenu: NSMenu) {
        let item = NSMenuItem()
        item.submenu = submenu
        addItem(item)
    }
}
