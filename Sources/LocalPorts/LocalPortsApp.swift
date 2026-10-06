import AppKit
import SwiftUI

@main
struct LocalPortsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store: PortStore

    init() {
        let store = PortStore()
        _store = StateObject(wrappedValue: store)
        HotKeyCenter.shared.bind(to: store.settings)
    }

    var body: some Scene {
        MenuBarExtra {
            PortsView(store: store)
        } label: {
            Image(nsImage: store.showsNewPortDot ? BrandAssets.menuIconBadged : BrandAssets.menuIcon)
                .accessibilityLabel(store.showsNewPortDot ? "Yolk, new ports" : "Yolk")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let identifier = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
