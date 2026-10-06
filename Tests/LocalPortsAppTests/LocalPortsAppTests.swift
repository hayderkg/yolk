import AppKit
import SwiftUI
import XCTest
import ServiceManagement
import LocalPortsCore
@testable import LocalPorts

@MainActor
final class LocalPortsAppTests: XCTestCase {
    func testSettingsPersistAndResetDoesNotChangeBehavior() async throws {
        let suite = "YolkSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.appearance = .dark
        settings.palette = .bubblegum
        settings.surface = .solid
        settings.setRefreshSeconds(10)
        let restored = AppSettings(defaults: defaults)
        XCTAssertEqual(restored.appearance, .dark)
        XCTAssertEqual(restored.palette, .bubblegum)
        XCTAssertEqual(restored.surface, .solid)
        XCTAssertEqual(restored.refreshSeconds, 10)
        restored.resetAppearance()
        XCTAssertEqual(restored.appearance, .system)
        XCTAssertEqual(restored.palette, .native)
        XCTAssertEqual(restored.surface, .translucent)
        XCTAssertEqual(restored.refreshSeconds, 10)
    }

    func testCorruptSettingsFallBackAndInvalidIntervalsAreRejected() async throws {
        let suite = "YolkSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for key in ["appearance", "palette", "surface"] { defaults.set("future-value", forKey: key) }
        defaults.set(-3, forKey: "refreshSeconds")
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.appearance, .system)
        XCTAssertEqual(settings.palette, .native)
        XCTAssertEqual(settings.surface, .translucent)
        XCTAssertEqual(settings.refreshSeconds, 3)
        settings.setRefreshSeconds(0)
        settings.setRefreshSeconds(999)
        XCTAssertEqual(settings.refreshSeconds, 3)
    }

    func testBrandResourcesAreAvailableAndMenuIconIsTemplateSized() async throws {
        XCTAssertNotNil(BrandAssets.appIcon)
        XCTAssertEqual(BrandAssets.logoOutline.boundingRect.width, 795, accuracy: 10)
        XCTAssertTrue(BrandAssets.logoOutline.boundingRect.contains(BrandAssets.logoYolk.boundingRect))
        XCTAssertTrue(BrandAssets.menuIcon.isTemplate)
        XCTAssertEqual(BrandAssets.menuIcon.size, NSSize(width: 23, height: 18))
    }

    func testLoginItemDoesNotRegisterAtLaunch() async {
        let backend = FakeLoginItem()
        let controller = LoginItemController(service: backend)
        controller.refresh()
        XCTAssertEqual(backend.registrations, 0)
        XCTAssertFalse(controller.isRegistered)
    }

    func testLoginItemTracksEnableDisableAndApproval() async {
        let backend = FakeLoginItem()
        backend.resultAfterRegister = .requiresApproval
        let controller = LoginItemController(service: backend)
        await controller.setEnabled(true)
        XCTAssertTrue(controller.isRegistered)
        XCTAssertTrue(controller.needsApproval)
        backend.status = .enabled
        controller.refresh()
        XCTAssertFalse(controller.needsApproval)
        await controller.setEnabled(false)
        XCTAssertFalse(controller.isRegistered)
        XCTAssertEqual(backend.registrations, 1)
        XCTAssertEqual(backend.removals, 1)
    }

    func testLoginFailureKeepsActualSystemStatus() async {
        let backend = FakeLoginItem()
        backend.shouldFail = true
        let controller = LoginItemController(service: backend)
        await controller.setEnabled(true)
        XCTAssertFalse(controller.isRegistered)
        XCTAssertNotNil(controller.error)
        XCTAssertFalse(controller.isUpdating)
    }

    func testPanelRepeatedlyShrinksAndExpandsWithoutMovingTopEdge() async {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 100, y: 200, width: 420, height: 500),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let sizing = MenuPanelSizing.SizingView()
        window.contentView = sizing
        let top = window.frame.maxY
        for height in [200.0, 500.0, 230.0, 520.0, 190.0] {
            sizing.desiredSize = CGSize(width: 420, height: height)
            sizing.fitWindow()
            XCTAssertEqual(window.contentRect(forFrameRect: window.frame).height, height, accuracy: 0.5)
            XCTAssertEqual(window.frame.maxY, top, accuracy: 0.5)
        }
    }

    func testInvalidPanelSizeDoesNotResizeHost() async {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 100, y: 200, width: 420, height: 500),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let sizing = MenuPanelSizing.SizingView()
        window.contentView = sizing
        let frame = window.frame
        sizing.desiredSize = CGSize(width: 420, height: CGFloat.nan)
        sizing.fitWindow()
        XCTAssertEqual(window.frame, frame)
    }

    func testScrollViewKeepsOverlayScrollersWhenSystemPrefersLegacy() async throws {
        let content = ScrollView { Color.clear.frame(height: 2000).overlayScrollers() }.frame(width: 300, height: 200)
        let window = NSWindow(contentRect: NSRect(x: 100, y: 200, width: 300, height: 200),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = NSHostingView(rootView: content)
        window.layoutIfNeeded()
        await Task.yield()
        let scrollView = try XCTUnwrap(Self.firstScrollView(in: window.contentView))
        XCTAssertEqual(scrollView.scrollerStyle, .overlay)
        scrollView.scrollerStyle = .legacy
        NotificationCenter.default.post(name: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil)
        let reapplied = expectation(description: "overlay reapplied")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { reapplied.fulfill() }
        await fulfillment(of: [reapplied], timeout: 2)
        XCTAssertEqual(scrollView.scrollerStyle, .overlay)
    }

    func testWindowAppearanceFollowsChosenModeAndReturnsToSystem() async {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 100, y: 200, width: 420, height: 500),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let probe = WindowAppearance.ProbeView()
        window.contentView = probe
        for (scheme, name) in [(ColorScheme.light, NSAppearance.Name.aqua), (.dark, .darkAqua)] {
            probe.colorScheme = scheme
            probe.apply()
            XCTAssertEqual(window.appearance?.name, name)
        }
        probe.colorScheme = nil
        probe.apply()
        XCTAssertNil(window.appearance)
    }

    func testNewPortsAreFlaggedOnceAndClearedWhenThePanelCloses() async throws {
        let suite = "YolkNewPortTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        func listener(pid: Int32, port: UInt16) -> Listener {
            Listener(process: ProcessIdentity(pid: pid, uid: 501, startSeconds: UInt64(pid), startMicroseconds: 0),
                     name: "node", port: port, addresses: ["127.0.0.1"])
        }
        let existing = listener(pid: 900_001, port: 5173), arrival = listener(pid: 900_002, port: 3000)
        let scans = ScanBox([existing])
        let store = PortStore(automaticallyRefresh: false, initialListeners: [existing], defaults: defaults, loadsIcons: false,
                              scan: { scans.value }, containers: { [] })
        await store.refresh()
        XCTAssertFalse(store.showsNewPortDot)
        scans.value = [existing, arrival]
        await store.refresh()
        XCTAssertEqual(store.newIDs, [arrival.id])
        XCTAssertTrue(store.showsNewPortDot)
        // A restart on the same port is the same service.
        scans.value = [existing, listener(pid: 900_003, port: 3000)]
        await store.refresh()
        XCTAssertTrue(store.newIDs.isEmpty)
        scans.value = [existing, arrival, listener(pid: 900_004, port: 8080)]
        await store.refresh()
        XCTAssertEqual(store.newIDs.map(\.port), [8080])
        store.setPanelVisible(true)
        XCTAssertFalse(store.showsNewPortDot)
        XCTAssertFalse(store.newIDs.isEmpty)
        store.setPanelVisible(false)
        XCTAssertTrue(store.newIDs.isEmpty)
        store.settings.newPortDot = false
        scans.value = [existing, arrival, listener(pid: 900_005, port: 9000)]
        await store.refresh()
        XCTAssertFalse(store.showsNewPortDot)
    }

    func testStoppingAContainerRowNeverSignalsTheEngineProcess() async throws {
        let suite = "YolkContainerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let engine = ProcessIdentity(pid: 900_010, uid: geteuid(), startSeconds: 1, startMicroseconds: 0)
        let first = Listener(process: engine, name: "com.docker.backend", port: 5433, addresses: ["::"])
        let second = Listener(process: engine, name: "com.docker.backend", port: 5434, addresses: ["::"])
        let container = ContainerInfo(id: "abc123", name: "shop-db-1", image: "postgres:16", ports: [5433, 5434])
        let stopped = ScanBox<String>([])
        let store = PortStore(automaticallyRefresh: false, defaults: defaults, loadsIcons: false, scan: { [first, second] },
                              containers: { [container] }, stopContainer: { stopped.value.append($0); return true })
        await store.refresh()
        XCTAssertEqual(store.service(for: first).container, container)
        XCTAssertEqual(store.service(for: first).category, .database)
        XCTAssertTrue(store.canStop(first))
        store.stopAll([first, second])
        XCTAssertTrue(store.isStopping(second))
        for _ in 0..<50 where !store.stoppingContainers.isEmpty { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(stopped.value, ["abc123"])
        XCTAssertTrue(store.termination.isEmpty)
        XCTAssertNil(store.message)
    }

    func testGlobalShortcutNeedsAModifierAndKeepsAReadableName() throws {
        func event(_ flags: NSEvent.ModifierFlags, _ characters: String, _ code: UInt16) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                                           characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
        }
        XCTAssertEqual(HotKey(event: try event([.command, .option], "p", 35))?.display, "⌥⌘P")
        XCTAssertEqual(HotKey(event: try event([.control, .shift], " ", 49))?.display, "⌃⇧Space")
        XCTAssertNil(HotKey(event: try event([], "p", 35)))
        XCTAssertNil(HotKey(event: try event([.shift], "P", 35)))
        let recorded = try XCTUnwrap(HotKey(event: try event([.command, .option], "p", 35)))
        XCTAssertEqual(try JSONDecoder().decode(HotKey.self, from: JSONEncoder().encode(recorded)), recorded)
        XCTAssertTrue(BrandAssets.menuIconBadged.isTemplate)
        XCTAssertNotEqual(BrandAssets.menuIconBadged.tiffRepresentation, BrandAssets.menuIcon.tiffRepresentation)
    }

    private static func firstScrollView(in view: NSView?) -> NSScrollView? {
        guard let view else { return nil }
        if let scrollView = view as? NSScrollView { return scrollView }
        for subview in view.subviews {
            if let found = firstScrollView(in: subview) { return found }
        }
        return nil
    }

    func testStorePersistsFavoritesAndHiddenInSeparateLaunch() async throws {
        let suite = "LocalPortsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let listener = Listener(process: ProcessIdentity(pid: 100, uid: 501, startSeconds: 1, startMicroseconds: 0), name: "node", port: 5173, addresses: ["::1"])
        let first = PortStore(automaticallyRefresh: false, initialListeners: [listener], defaults: defaults)
        first.toggleFavorite(listener)
        first.toggleHidden(listener)
        let second = PortStore(automaticallyRefresh: false, initialListeners: [listener], defaults: defaults)
        XCTAssertTrue(second.isFavorite(listener))
        XCTAssertTrue(second.isHidden(listener))
        second.restoreAllHidden()
        XCTAssertFalse(second.isHidden(listener))
    }
}

@MainActor
private final class FakeLoginItem: LoginItemService {
    var status = SMAppService.Status.notRegistered
    var resultAfterRegister = SMAppService.Status.enabled
    var registrations = 0
    var removals = 0
    var shouldFail = false
    func register() throws {
        registrations += 1
        if shouldFail { throw NSError(domain: "TestLoginFailure", code: 1) }
        status = resultAfterRegister
    }
    func unregister() async throws { removals += 1; status = .notRegistered }
}

private final class ScanBox<Element>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Element]
    init(_ value: [Element]) { stored = value }
    var value: [Element] {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}
