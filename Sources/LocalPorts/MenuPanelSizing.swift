import AppKit
import SwiftUI

/// Keeps the MenuBarExtra host fitted to its intrinsic content, with its top edge anchored.
/// SwiftUI can otherwise keep the previous panel height after a ScrollView shrinks.
struct MenuPanelSizing: NSViewRepresentable {
    let size: CGSize
    func makeNSView(context: Context) -> SizingView { SizingView() }
    func updateNSView(_ view: SizingView, context: Context) {
        view.desiredSize = size
        view.scheduleResize()
    }

    final class SizingView: NSView {
        var desiredSize: CGSize = .zero
        private var resizeScheduled = false
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); scheduleResize() }

        func scheduleResize() {
            guard !resizeScheduled else { return }
            resizeScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.resizeScheduled = false
                self.fitWindow()
            }
        }

        func fitWindow() {
            guard let window, desiredSize.width > 0, desiredSize.height > 0,
                  desiredSize.width.isFinite, desiredSize.height.isFinite else { return }
            let size = CGSize(width: ceil(desiredSize.width), height: ceil(desiredSize.height))
            let content = window.contentRect(forFrameRect: window.frame)
            guard abs(content.width - size.width) > 0.5 || abs(content.height - size.height) > 0.5 else { return }
            let frameSize = window.frameRect(forContentRect: CGRect(origin: .zero, size: size)).size
            var frame = window.frame
            frame.origin.y = frame.maxY - frameSize.height
            frame.size = frameSize
            // Do not animate the host size: it must stay in sync with SwiftUI's content.
            window.setFrame(frame, display: true, animate: false)
            window.invalidateShadow()
        }
    }
}
