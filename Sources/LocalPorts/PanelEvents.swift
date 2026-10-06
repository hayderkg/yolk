import AppKit
import SwiftUI

/// Reports when the panel window is shown or hidden and offers its key presses to the list first.
struct PanelEvents: NSViewRepresentable {
    var onVisibility: (Bool) -> Void
    /// Return true to consume the event.
    var onKeyDown: (NSEvent) -> Bool

    func makeNSView(context: Context) -> ProbeView { ProbeView() }
    func updateNSView(_ view: ProbeView, context: Context) {
        view.onVisibility = onVisibility
        view.onKeyDown = onKeyDown
    }

    final class ProbeView: NSView {
        var onVisibility: (Bool) -> Void = { _ in }
        var onKeyDown: (NSEvent) -> Bool = { _ in false }
        private var monitor: Any?
        private var observers: [NSObjectProtocol] = []
        private var reported: Bool?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            teardown()
            guard let window else { report(false); return }
            for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didBecomeKeyNotification, NSWindow.willCloseNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] note in
                    self?.report(note.name != NSWindow.willCloseNotification && self?.window?.isVisible == true)
                })
            }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let window = self.window, event.window === window, window.attachedSheet == nil else { return event }
                return self.onKeyDown(event) ? nil : event
            }
            report(window.isVisible)
        }

        private func report(_ visible: Bool) {
            guard reported != visible else { return }
            reported = visible
            // Never publish from inside a SwiftUI view update.
            DispatchQueue.main.async { [weak self] in self?.onVisibility(visible) }
        }

        private func teardown() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
        }

        deinit { teardown() }
    }
}

/// Fades content in with a slight drop when it appears, leaving layout (and the panel size) untouched.
private struct AppearEffect: ViewModifier {
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.opacity(shown ? 1 : 0).offset(y: shown || reduceMotion ? 0 : -5)
            .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { shown = true } }
    }
}

extension View {
    func appearEffect() -> some View { modifier(AppearEffect()) }
}

/// Editors and terminals offered for a project folder, limited to the ones installed.
enum ProjectApps {
    private static let known = [
        ("Cursor", "com.todesktop.230313mzl4w4u92"), ("Visual Studio Code", "com.microsoft.VSCode"), ("Zed", "dev.zed.Zed"),
        ("Windsurf", "com.exafunction.windsurf"), ("Sublime Text", "com.sublimetext.4"),
        ("Terminal", "com.apple.Terminal"), ("iTerm", "com.googlecode.iterm2"), ("Ghostty", "com.mitchellh.ghostty"), ("Warp", "dev.warp.Warp-Stable")
    ]
    static let installed: [(name: String, url: URL)] = known.compactMap { name, identifier in
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier).map { (name, $0) }
    }

    static func open(_ directory: URL, with application: URL) {
        NSWorkspace.shared.open([directory], withApplicationAt: application, configuration: NSWorkspace.OpenConfiguration())
    }
}
