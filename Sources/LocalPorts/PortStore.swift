import AppKit
import SwiftUI
import LocalPortsCore

@MainActor
final class PortStore: ObservableObject {
    enum TerminationState { case waiting, forceAvailable, forcing }

    @Published private(set) var listeners: [Listener] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var hasLoaded = false
    @Published private(set) var scanFailed = false
    @Published private(set) var termination: [ProcessIdentity: TerminationState] = [:]
    @Published private(set) var services: [Listener.ID: ServiceIdentity] = [:]
    @Published private(set) var icons: [Listener.ID: NSImage] = [:]
    @Published private(set) var preferences: ServicePreferences
    @Published var message: String?
    @Published private(set) var stoppingContainers: Set<String> = []
    /// Rows that appeared while the panel was closed, or since it opened. Cleared when it closes.
    @Published private(set) var newIDs: Set<Listener.ID> = []
    @Published private(set) var panelVisible = false
    private var lastSeen: [String: Date] = [:]
    private var refreshLoop: Task<Void, Never>?
    private var iconAttempts: [Listener.ID: Date] = [:]
    private var iconsLoading: Set<Listener.ID> = []
    let settings: AppSettings
    private let defaults: UserDefaults
    private let scan: @Sendable () throws -> [Listener]
    private let loadsIcons: Bool
    private let containers: @Sendable () -> [ContainerInfo]
    private let stopContainer: @Sendable (String) -> Bool

    init(automaticallyRefresh: Bool = true, initialListeners: [Listener] = [],
         initialServices: [Listener.ID: ServiceIdentity] = [:], defaults: UserDefaults = .standard, loadsIcons: Bool = true,
         scan: @escaping @Sendable () throws -> [Listener] = { try ProcessInspector.scan() },
         containers: @escaping @Sendable () -> [ContainerInfo] = { Docker.containers() },
         stopContainer: @escaping @Sendable (String) -> Bool = { Docker.stop(containerID: $0) }) {
        self.defaults = defaults
        self.settings = AppSettings(defaults: defaults)
        self.scan = scan
        self.containers = containers
        self.stopContainer = stopContainer
        self.loadsIcons = loadsIcons
        self.preferences = ServicePreferences(data: defaults.data(forKey: "savedServices"))
        self.listeners = initialListeners
        self.services = initialServices
        self.hasLoaded = !automaticallyRefresh
        for listener in initialListeners {
            lastSeen[ServicePreferences.key(for: listener, service: service(for: listener))] = Date()
        }
        guard automaticallyRefresh else { return }
        refreshLoop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                do { try await Task.sleep(for: .seconds(self?.settings.refreshSeconds ?? 3)) } catch { return }
            }
        }
    }

    deinit { refreshLoop?.cancel() }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false; hasLoaded = true }
        do {
            let cached = services
            let scan = self.scan
            let containers = self.containers
            let snapshot = try await Task.detached(priority: .utility) {
                let listeners = try scan()
                // Only ask the container engine when one of its proxies is actually listening.
                var published: [UInt16: ContainerInfo] = [:]
                if listeners.contains(where: { Docker.isProxy($0.name) }) {
                    for container in containers() { for port in container.ports { published[port] = container } }
                }
                var identities: [Listener.ID: ServiceIdentity] = [:]
                var details: [ProcessIdentity: ProcessDetails] = [:]
                for listener in listeners {
                    let container = Docker.isProxy(listener.name) ? published[listener.port] : nil
                    if let previous = cached[listener.id], previous.container == container { identities[listener.id] = previous; continue }
                    let info = details[listener.process] ?? ProcessInspector.details(for: listener.process)
                    details[listener.process] = info
                    identities[listener.id] = ServiceIdentity(listener: listener, details: info, container: container)
                }
                return (listeners, identities)
            }.value
            let result = snapshot.0
            trackNew(result, services: snapshot.1)
            if listeners != result { listeners = result }
            if services != snapshot.1 { services = snapshot.1 }
            let live = Set(result.map(\.process))
            termination = termination.filter { live.contains($0.key) }
            let liveRows = Set(result.map(\.id))
            icons = icons.filter { liveRows.contains($0.key) }
            iconAttempts = iconAttempts.filter { liveRows.contains($0.key) }
            if scanFailed { message = nil }
            scanFailed = false
        } catch {
            scanFailed = true
            message = "Couldn't refresh. \(error.localizedDescription)"
        }
    }

    /// A restart on the same port within a minute is the same service, not a new one.
    private func trackNew(_ result: [Listener], services: [Listener.ID: ServiceIdentity]) {
        let now = Date()
        var added: Set<Listener.ID> = []
        for listener in result {
            let service = services[listener.id] ?? ServiceIdentity(listener: listener)
            let key = ServicePreferences.key(for: listener, service: service)
            if hasLoaded, lastSeen[key] == nil, service.category != .system, !preferences.isHidden(listener, service: service) {
                added.insert(listener.id)
            }
            lastSeen[key] = now
        }
        lastSeen = lastSeen.filter { now.timeIntervalSince($0.value) < 60 }
        let live = Set(result.map(\.id))
        let updated = newIDs.union(added).intersection(live)
        if updated != newIDs { newIDs = updated }
    }

    var showsNewPortDot: Bool { settings.newPortDot && !panelVisible && !newIDs.isEmpty }

    func setPanelVisible(_ visible: Bool) {
        guard panelVisible != visible else { return }
        panelVisible = visible
        if !visible { newIDs = [] }
    }

    func webURL(for listener: Listener) -> URL? { service(for: listener).webURL(for: listener) }
    func canStop(_ listener: Listener) -> Bool { service(for: listener).container != nil || listener.process.canTerminate }
    func isStopping(_ listener: Listener) -> Bool {
        if let container = service(for: listener).container { return stoppingContainers.contains(container.id) }
        return termination[listener.process] == .waiting || termination[listener.process] == .forcing
    }

    /// Stops each process or container once, however many of its ports are listed.
    func stopAll(_ rows: [Listener]) {
        var processes: Set<ProcessIdentity> = []
        var containerIDs: Set<String> = []
        for listener in rows {
            if let container = service(for: listener).container {
                if containerIDs.insert(container.id).inserted { stop(listener) }
            } else if processes.insert(listener.process).inserted { stop(listener) }
        }
    }

    private func stop(_ container: ContainerInfo) {
        guard !scanFailed, !stoppingContainers.contains(container.id) else { return }
        stoppingContainers.insert(container.id)
        let stopContainer = self.stopContainer
        Task {
            let stopped = await Task.detached(priority: .userInitiated) { stopContainer(container.id) }.value
            stoppingContainers.remove(container.id)
            if !stopped { message = "Couldn't stop the container \(container.name)." }
            await refresh()
        }
    }

    func stop(_ listener: Listener, force: Bool = false) {
        // A container row stops the container, never the engine process that publishes its port.
        if let container = service(for: listener).container { stop(container); return }
        let identity = listener.process
        guard identity.canTerminate, !scanFailed else { return }
        if force {
            guard termination[identity] == .forceAvailable else { return }
        } else {
            guard termination[identity] == nil else { return }
        }
        do {
            try ProcessInspector.terminate(identity, force: force)
            termination[identity] = force ? .forcing : .waiting
            Task {
                try? await Task.sleep(for: .seconds(force ? 0.4 : 2))
                if ProcessInspector.isRunning(identity) {
                    termination[identity] = .forceAvailable
                } else {
                    termination[identity] = nil
                }
                await refresh()
            }
        } catch {
            message = error.localizedDescription
            Task { await refresh() }
        }
    }

    func open(_ url: URL) {
        if !NSWorkspace.shared.open(url) { message = "Couldn't open the default browser." }
    }

    func service(for listener: Listener) -> ServiceIdentity {
        services[listener.id] ?? ServiceIdentity(listener: listener)
    }

    func isFavorite(_ listener: Listener) -> Bool { preferences.isFavorite(listener, service: service(for: listener)) }
    func isHidden(_ listener: Listener) -> Bool { preferences.isHidden(listener, service: service(for: listener)) }
    func toggleFavorite(_ listener: Listener) {
        preferences.toggleFavorite(listener, service: service(for: listener))
        savePreferences()
    }
    func toggleHidden(_ listener: Listener) {
        preferences.toggleHidden(listener, service: service(for: listener))
        savePreferences()
    }
    func restoreHidden(key: String) { preferences.restoreHidden(key: key); savePreferences() }
    func restoreAllHidden() { preferences.restoreAllHidden(); savePreferences() }
    private func savePreferences() { defaults.set(preferences.data, forKey: "savedServices") }

    func loadIcon(for listener: Listener) async {
        guard loadsIcons, !iconsLoading.contains(listener.id),
              iconAttempts[listener.id].map({ Date().timeIntervalSince($0) > 600 }) ?? true else { return }
        iconsLoading.insert(listener.id)
        iconAttempts[listener.id] = Date()
        defer { iconsLoading.remove(listener.id) }
        let identity = service(for: listener)
        if let image = IconLoader.appIcon(for: listener, service: identity) {
            icons[listener.id] = image
            return
        }
        let data = await Task.detached(priority: .utility) {
            await IconLoader.faviconData(for: listener, service: identity)
        }.value
        guard listeners.contains(where: { $0.id == listener.id }),
              let data, let image = IconLoader.decode(data) else { return }
        icons[listener.id] = image
    }
}
