import AppKit
import SwiftUI
import LocalPortsCore

struct ServiceRow: View {
    static let height: CGFloat = 52

    @ObservedObject var store: PortStore
    let listener: Listener
    let selected: Bool
    let copied: Bool
    let activate: () -> Void
    let copy: () -> Void
    let requestStop: () -> Void
    @State private var hovered = false
    @Environment(\.portTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var service: ServiceIdentity { store.service(for: listener) }
    private var title: String { service.projectName ?? listener.name }
    private var favorite: Bool { store.isFavorite(listener) }
    private var hidden: Bool { store.isHidden(listener) }
    private var isNew: Bool { store.newIDs.contains(listener.id) }
    private var webURL: URL? { store.webURL(for: listener) }
    private var stopState: PortStore.TerminationState? { service.container == nil ? store.termination[listener.process] : nil }
    /// Actions stay out of the way until the row is pointed at, selected, or mid-stop.
    private var showsActions: Bool { hovered || selected || stopState != nil || store.isStopping(listener) }

    private var detail: String {
        if let container = service.container { return "Docker · \(container.imageName)" }
        if let command = service.command, command != title { return command }
        return service.projectName == nil ? "PID \(String(listener.process.pid))" : "\(listener.name) · PID \(String(listener.process.pid))"
    }

    private var tooltip: String {
        var lines = ["\(listener.name) · PID \(listener.process.pid)", "\(listener.addresses.sorted().joined(separator: ", ")):\(listener.port)"]
        if let container = service.container { lines.append("Container \(container.name) · \(container.image)") }
        if let command = service.command { lines.append(command) }
        if let directory = service.projectDirectory { lines.append(directory.path) }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        HStack(spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    if favorite {
                        Image(systemName: "star.fill").font(.system(size: 8)).foregroundStyle(theme.accent)
                            .transition(.scale(scale: 0.2).combined(with: .opacity)).accessibilityHidden(true)
                    }
                    if isNew {
                        Circle().fill(theme.accent).frame(width: 5, height: 5)
                            .transition(.scale.combined(with: .opacity)).help("New since you last looked").accessibilityLabel("New")
                    }
                }
                HStack(spacing: 3) {
                    if hidden { Image(systemName: "eye.slash").font(.system(size: 8)) }
                    Text(detail).truncationMode(.tail)
                    if service.container == nil {
                        // The engine's own uptime would say nothing about a container.
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            Text("· \(Uptime.short(context.date.timeIntervalSince(listener.process.startDate)))")
                        }.layoutPriority(1)
                    }
                }
                .font(.system(size: 10, design: .monospaced)).lineLimit(1).foregroundStyle(.secondary)
            }
            .opacity(hidden ? 0.6 : 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(tooltip)
            portButton
            if showsActions { actions.transition(.opacity) }
        }
        .padding(.horizontal, 8).frame(height: Self.height - 2)
        .background(selected ? theme.accent.opacity(0.14) : Color.primary.opacity(hovered ? 0.05 : 0), in: RoundedRectangle(cornerRadius: 7))
        .padding(.horizontal, 8).frame(height: Self.height).contentShape(Rectangle())
        .onTapGesture(perform: activate)
        .onHover { hovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: showsActions)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.55), value: favorite)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isNew)
        .contextMenu { menu }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title), \(listener.name), PID \(listener.process.pid), port \(listener.port)")
        .accessibilityAction(named: webURL == nil ? "Copy address" : "Open in browser", activate)
        .task { await store.loadIcon(for: listener) }
    }

    private var portButton: some View {
        Button(action: copy) {
            VStack(alignment: .trailing, spacing: 3) {
                Text(copied ? "Copied" : ":\(String(listener.port))")
                    .font(.system(size: 12, weight: .medium, design: copied ? .default : .monospaced))
                    .foregroundStyle(copied ? theme.accent : Color.secondary)
                    .id(copied).transition(.opacity)
                Label(listener.listensOnAllInterfaces ? "All" : "Local", systemImage: listener.listensOnAllInterfaces ? "network" : "desktopcomputer")
                    .font(.system(size: 8)).foregroundStyle(.secondary)
            }
            .frame(minWidth: 52, alignment: .trailing).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: copied)
        .help("Click to copy \(listener.host):\(String(listener.port))\n" + (listener.listensOnAllInterfaces ? "Listening on all interfaces. Access from other devices depends on your network and firewall." : "Listening only on this Mac's local addresses."))
        .accessibilityLabel("Port \(listener.port), \(listener.listensOnAllInterfaces ? "all interfaces" : "localhost only"). Copy address")
    }

    private var actions: some View {
        HStack(spacing: 2) {
            Button { store.toggleFavorite(listener) } label: {
                Image(systemName: favorite ? "star.fill" : "star")
                    .foregroundStyle(favorite ? theme.accent : Color.secondary).frame(width: 22, height: 28)
            }
            .buttonStyle(.borderless).help(favorite ? "Remove from favorites" : "Add to favorites")
            .accessibilityLabel("\(favorite ? "Remove" : "Add") \(title) \(favorite ? "from" : "to") favorites")
            Button { if let webURL { store.open(webURL) } } label: {
                Image(systemName: "arrow.up.right.square").frame(width: 24, height: 28)
            }
            .buttonStyle(.borderless).disabled(webURL == nil || store.scanFailed)
            .help(webURL.map { "Open \($0.absoluteString)" } ?? "TCP service with no known web page. Right-click to open it as HTTP.")
            .accessibilityLabel("Open port \(listener.port) in the browser")
            stopButton
        }
    }

    @ViewBuilder private var menu: some View {
        Button(favorite ? "Remove from favorites" : "Add to favorites") { store.toggleFavorite(listener) }
        Button(hidden ? "Show service" : "Hide service") { store.toggleHidden(listener) }
        Divider()
        if let directory = service.projectDirectory {
            Menu("Open project in") {
                Button("Finder") { store.open(directory) }
                ForEach(ProjectApps.installed, id: \.url) { app in
                    Button(app.name) { ProjectApps.open(directory, with: app.url) }
                }
            }
        }
        Button("Copy address", action: copy)
        if webURL == nil { Button("Open as HTTP") { store.open(listener.httpURL) }.disabled(store.scanFailed) }
    }

    @ViewBuilder private var icon: some View {
        Group {
            if let image = store.icons[listener.id] {
                Image(nsImage: image).resizable().scaledToFit().transition(.opacity)
            } else {
                Text(ServiceIdentity.initials(for: title)).font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary).frame(width: 24, height: 24)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
            }
        }
        .frame(width: 24, height: 24).accessibilityHidden(true)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: store.icons[listener.id] != nil)
    }

    @ViewBuilder private var stopButton: some View {
        let subject = service.container.map { "container \($0.name)" } ?? listener.name
        if store.isStopping(listener) {
            ProgressView().controlSize(.small).frame(width: 24, height: 28)
                .help("Stopping \(subject)…").accessibilityLabel("Stopping \(subject)")
        } else {
            Button(role: .destructive, action: requestStop) {
                Image(systemName: stopState == .forceAvailable ? "xmark.octagon" : "stop.circle")
                    .foregroundStyle(stopState == .forceAvailable ? Color.red : Color.secondary).frame(width: 24, height: 28)
            }
            .buttonStyle(.borderless).disabled(!store.canStop(listener) || store.scanFailed)
            .help(!store.canStop(listener) ? "Your user can't stop this process." :
                  stopState == .forceAvailable ? "Still running. Force quit…" :
                  service.container != nil ? "Stop \(subject)" : "Stop \(listener.name) and all of its ports")
            .accessibilityLabel(stopState == .forceAvailable ? "Force quit \(listener.name)" : "Stop \(subject)")
        }
    }
}
