import AppKit
import Carbon.HIToolbox
import Combine

/// A system-wide shortcut that toggles the panel. Stored with its display form.
struct HotKey: Codable, Equatable {
    let keyCode: UInt32
    let carbonModifiers: UInt32
    let display: String

    private static let named: [UInt16: String] = [
        49: "Space", 36: "↩", 48: "⇥", 123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"
    ]

    /// Nil unless the event carries ⌘, ⌥ or ⌃, so plain typing can never become a global shortcut.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !flags.intersection([.command, .option, .control]).isEmpty else { return nil }
        guard let key = Self.named[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased(),
              !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        var modifiers: UInt32 = 0
        var symbols = ""
        if flags.contains(.control) { modifiers |= UInt32(controlKey); symbols += "⌃" }
        if flags.contains(.option) { modifiers |= UInt32(optionKey); symbols += "⌥" }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey); symbols += "⇧" }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey); symbols += "⌘" }
        keyCode = UInt32(event.keyCode)
        carbonModifiers = modifiers
        display = symbols + key
    }
}

@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var subscription: AnyCancellable?

    func bind(to settings: AppSettings) {
        subscription = settings.$hotKey.removeDuplicates().sink { [weak self] in self?.register($0) }
    }

    private func register(_ hotKey: HotKey?) {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        guard let hotKey else { return }
        if handlerRef == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                Task { @MainActor in MenuPanel.toggle() }
                return noErr
            }, 1, &spec, nil, &handlerRef)
        }
        // 'YOLK'
        RegisterEventHotKey(hotKey.keyCode, hotKey.carbonModifiers, EventHotKeyID(signature: 0x594F4C4B, id: 1),
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }
}

@MainActor
enum MenuPanel {
    /// MenuBarExtra has no public way to present its window, so drive its status item.
    static func toggle() {
        for window in NSApp.windows {
            guard let button = statusButton(in: window.contentView) else { continue }
            NSApp.activate(ignoringOtherApps: true)
            // macOS 27 presents status item windows through expanded-interface sessions and no longer
            // routes clicks through the button. Every selector is checked, so an OS change degrades to a no-op.
            let itemKey = Selector(("statusItem")), sessionKey = Selector(("expandedInterfaceSession"))
            let request = Selector(("_requestExpandedInterfaceSession")), cancel = Selector(("cancel"))
            if window.responds(to: itemKey), let item = window.perform(itemKey)?.takeUnretainedValue() as? NSStatusItem,
               item.responds(to: sessionKey), item.responds(to: request) {
                if let session = item.perform(sessionKey)?.takeUnretainedValue() as? NSObject {
                    if session.responds(to: cancel) { session.perform(cancel) }
                } else { item.perform(request) }
            } else { button.performClick(nil) }
            return
        }
    }

    private static func statusButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let button = view as? NSStatusBarButton { return button }
        for subview in view.subviews {
            if let button = statusButton(in: subview) { return button }
        }
        return nil
    }
}
