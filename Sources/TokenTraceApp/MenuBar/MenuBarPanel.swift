import AppKit

/// Borderless, arrow-free dropdown for the menu bar status item.
///
/// `NSPopover` has no public API to suppress its arrow, so menu-bar apps
/// that want a flat dropdown (Stats, Bartender, iStat Menus, etc.) use a
/// custom `NSPanel`. This is that.
///
/// Responsibilities are minimal: borderless chrome with a rounded mask,
/// floating panel level so it stays above other windows, and "non-activating"
/// so opening the panel doesn't steal focus from the foreground app. All
/// content layout lives in the SwiftUI view installed as `contentView`.
@MainActor
final class MenuBarPanel: NSPanel {
    init(contentView: NSView, cornerRadius: CGFloat = 10) {
        super.init(
            contentRect: contentView.bounds,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        self.level = .popUpMenu
        self.hasShadow = true
        self.isMovable = false
        self.isMovableByWindowBackground = false
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hidesOnDeactivate = false

        // Rounded mask for the SwiftUI content. The window-level shadow above
        // is drawn from this masked layer's outline.
        contentView.wantsLayer = true
        if let layer = contentView.layer {
            layer.cornerRadius = cornerRadius
            layer.cornerCurve = .continuous
            layer.masksToBounds = true
        }
        self.contentView = contentView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
