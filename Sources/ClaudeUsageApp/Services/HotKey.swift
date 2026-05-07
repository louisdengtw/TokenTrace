import AppKit
import Carbon.HIToolbox
import OSLog

/// Carbon-based registration of a global ⌘U hotkey that toggles the popover.
///
/// Carbon is still the supported AppKit-friendly route in macOS 13–14 for non-sandboxed
/// global hotkeys; the `NSEvent.addGlobalMonitorForEvents(matching:)` path requires
/// Accessibility but cannot intercept the keystroke (the event still reaches the active app).
@MainActor
final class HotKey {
    static let shared = HotKey()

    private let log = Logger(subsystem: "dev.louisdeng.claudeusage", category: "HotKey")
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var handler: (() -> Void)?

    private init() {}

    @discardableResult
    func register(handler: @escaping () -> Void) -> Bool {
        unregister()
        self.handler = handler

        installEventHandlerIfNeeded()

        let hotKeyId = EventHotKeyID(signature: OSType(0x434C4458 /* 'CLDX' */), id: 1)
        let modifiers = UInt32(cmdKey)
        let keyCode = UInt32(kVK_ANSI_U)

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyId,
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            log.error("RegisterEventHotKey failed status=\(status, privacy: .public)")
            self.handler = nil
            return false
        }
        self.hotKeyRef = ref
        return true
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        handler = nil
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let context = Unmanaged.passUnretained(self).toOpaque()

        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, _, ctx in
                guard let ctx else { return noErr }
                let me = Unmanaged<HotKey>.fromOpaque(ctx).takeUnretainedValue()
                DispatchQueue.main.async {
                    me.handler?()
                }
                return noErr
            },
            1,
            &spec,
            context,
            &eventHandler
        )

        if status != noErr {
            log.error("InstallEventHandler failed status=\(status, privacy: .public)")
        }
    }
}
