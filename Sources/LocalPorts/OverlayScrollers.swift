import AppKit
import SwiftUI

/// Forces the enclosing ScrollView to use overlay scrollers, whatever the system setting says.
/// Legacy scrollers (mouse connected, or "Show scroll bars: Always") would otherwise take list width.
struct OverlayScrollers: NSViewRepresentable {
    func makeNSView(context: Context) -> ProbeView { ProbeView() }
    func updateNSView(_ view: ProbeView, context: Context) { view.apply() }

    final class ProbeView: NSView {
        private var styleObserver: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let styleObserver { NotificationCenter.default.removeObserver(styleObserver) }
            styleObserver = nil
            guard window != nil else { return }
            // NSScrollView adopts the new system style on this notification, so reapply after it.
            styleObserver = NotificationCenter.default.addObserver(
                forName: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                DispatchQueue.main.async { self?.apply() }
            }
            apply()
            DispatchQueue.main.async { [weak self] in self?.apply() }
        }

        func apply() {
            guard let scrollView = enclosingScrollView, scrollView.scrollerStyle != .overlay else { return }
            scrollView.scrollerStyle = .overlay
        }

        deinit {
            if let styleObserver { NotificationCenter.default.removeObserver(styleObserver) }
        }
    }
}

extension View {
    /// Apply to the content of a ScrollView, not to the ScrollView itself.
    func overlayScrollers() -> some View {
        background(OverlayScrollers().frame(width: 0, height: 0).accessibilityHidden(true))
    }
}
