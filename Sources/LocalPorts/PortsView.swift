import AppKit
import SwiftUI
import LocalPortsCore

@MainActor
struct PortsView: View {
    @ObservedObject var store: PortStore
    @ObservedObject private var settings: AppSettings
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var settingsVisible = false
    @StateObject private var login: LoginItemController
    @State private var forceTarget: Listener?
    @State private var query = ""
    @State private var searchVisible = false
    @State private var favoritesOnly = false
    @State private var showHidden = false
    @State private var lastToggledGroup: String?
    @State private var selection: Listener.ID?
    /// True once the arrow keys chose the row, as opposed to search preselecting the top hit.
    @State private var navigated = false
    @State private var typingAhead = false
    @State private var copiedID: Listener.ID?
    @State private var stopAllTarget: Group?
    @State private var refreshTurns = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searchFocused: Bool
    @AppStorage private var groupByType: Bool
    @AppStorage private var collapsedGroups: String

    init(store: PortStore, defaults: UserDefaults = .standard, login: LoginItemController? = nil, initiallyShowsSettings: Bool = false) {
        self.store = store
        self.settings = store.settings
        _settingsVisible = State(initialValue: initiallyShowsSettings)
        _login = StateObject(wrappedValue: login ?? LoginItemController())
        _groupByType = AppStorage(wrappedValue: true, "groupByType", store: defaults)
        _collapsedGroups = AppStorage(wrappedValue: "", "collapsedGroups", store: defaults)
    }

    private struct Group: Identifiable {
        let id: String
        let title: String
        let rows: [Listener]
    }

    private var visible: [Listener] {
        ServiceList.filtered(store.listeners, services: store.services, preferences: store.preferences,
                             query: query, favoritesOnly: favoritesOnly, showHidden: showHidden)
    }

    private var groups: [Group] {
        let favorites = visible.filter(store.isFavorite)
        var result = favorites.isEmpty ? [] : [Group(id: "favorites", title: "Favorites", rows: favorites)]
        for category in ServiceCategory.allCases {
            let rows = visible.filter { !store.isFavorite($0) && store.service(for: $0).category == category }
            if !rows.isEmpty { result.append(Group(id: category.rawValue, title: category.title, rows: rows)) }
        }
        return result
    }

    private var searching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private func isCollapsed(_ id: String) -> Bool {
        !searching && collapsedGroups.split(separator: ",").contains(Substring(id))
    }
    private var listHeight: CGFloat {
        guard !visible.isEmpty else { return 144 }
        if !groupByType { return min(CGFloat(visible.count) * ServiceRow.height, 406) }
        return min(groups.reduce(CGFloat(0)) { result, group in
            result + 30 + (isCollapsed(group.id) ? 0 : CGFloat(group.rows.count) * ServiceRow.height)
        }, 420)
    }

    /// Rows the arrow keys can reach, in display order.
    private var navigable: [Listener] {
        groupByType ? groups.filter { !isCollapsed($0.id) }.flatMap(\.rows) : visible
    }
    private var selectedListener: Listener? { navigable.first { $0.id == selection } }

    private var theme: PortTheme {
        PortTheme(palette: settings.palette, dark: (settings.appearance.colorScheme ?? systemColorScheme) == .dark,
                  translucent: settings.surface == .translucent)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if searchVisible && !settingsVisible { searchBar.appearEffect() }
            Divider()
            if let message = store.message ?? login.error { messageBar(message) }
            if settingsVisible { SettingsPanel(settings: settings, login: login).appearEffect() }
            else {
                VStack(spacing: 0) {
                    if visible.isEmpty { emptyState.frame(height: listHeight) } else { list }
                }.appearEffect()
            }
            Divider()
            footer
        }
        .frame(width: 420)
        .fixedSize(horizontal: true, vertical: true)
        .background(ThemeSurface())
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .background(GeometryReader { geometry in MenuPanelSizing(size: geometry.size) })
        .environment(\.portTheme, theme)
        .tint(theme.accent)
        .preferredColorScheme(settings.appearance.colorScheme)
        .background(WindowAppearance(colorScheme: settings.appearance.colorScheme))
        .background(PanelEvents(onVisibility: { visible in
            store.setPanelVisible(visible)
            if visible { selection = nil; navigated = false }
        }, onKeyDown: handleKey))
        .onDisappear { store.setPanelVisible(false) }
        .onChange(of: query) { _ in
            navigated = false
            selection = searching ? navigable.first?.id : nil
        }
        .onAppear { login.refresh(); Task { await store.refresh() } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in login.refresh() }
        .alert("Force quit \(forceTarget?.name ?? "this process")?", isPresented: Binding(
            get: { forceTarget != nil }, set: { if !$0 { forceTarget = nil } }
        ), presenting: forceTarget) { target in
            Button("Cancel", role: .cancel) { forceTarget = nil }
            Button("Force Quit", role: .destructive) { store.stop(target, force: true); forceTarget = nil }
        } message: { target in
            Text("Process \(target.process.pid) is still running after being asked to quit. Forcing it will close all of its ports and may lose unsaved work.")
        }
        .alert("Stop everything in \(stopAllTarget?.title ?? "this group")?", isPresented: Binding(
            get: { stopAllTarget != nil }, set: { if !$0 { stopAllTarget = nil } }
        ), presenting: stopAllTarget) { group in
            Button("Cancel", role: .cancel) { stopAllTarget = nil }
            Button("Stop All", role: .destructive) { store.stopAll(group.rows.filter(store.canStop)); stopAllTarget = nil }
        } message: { group in
            Text("\(group.rows.filter(store.canStop).count) services will be asked to quit. Stopping a process closes every port it has open.")
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard !settingsVisible, forceTarget == nil, stopAllTarget == nil else { return false }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let editor = event.window?.firstResponder as? NSTextView
        if typingAhead, let editor {
            // Focusing the field selected the first typed character; keep it and continue after it.
            typingAhead = false
            let length = (editor.string as NSString).length
            if length > 0, editor.selectedRange().length == length { editor.setSelectedRange(NSRange(location: length, length: 0)) }
        }
        switch event.keyCode {
        case 125, 126:
            guard flags.isEmpty, !navigable.isEmpty else { return false }
            moveSelection(by: event.keyCode == 125 ? 1 : -1)
            return true
        case 36, 76:
            guard flags.isEmpty, let listener = selectedListener else { return false }
            activate(listener)
            return true
        case 51 where flags == .command:
            // While typing a query, ⌘⌫ belongs to the text field unless a row was chosen on purpose.
            guard navigated || editor == nil, let listener = selectedListener, store.canStop(listener) else { return false }
            requestStop(listener)
            return true
        case 8 where flags == .command:
            guard let listener = selectedListener, (editor?.selectedRange().length ?? 0) == 0 else { return false }
            copyAddress(listener)
            return true
        default:
            guard editor == nil, flags.subtracting(.shift).isEmpty, let typed = event.characters,
                  typed.unicodeScalars.count == 1, let scalar = typed.unicodeScalars.first,
                  CharacterSet.alphanumerics.union(.punctuationCharacters).union(.symbols).contains(scalar) else { return false }
            searchVisible = true
            query += typed
            typingAhead = true
            DispatchQueue.main.async { searchFocused = true }
            return true
        }
    }

    private func moveSelection(by offset: Int) {
        let rows = navigable
        let current = rows.firstIndex { $0.id == selection }
        let next = current.map { min(max($0 + offset, 0), rows.count - 1) } ?? (offset > 0 ? 0 : rows.count - 1)
        navigated = true
        selection = rows[next].id
    }

    /// Primary action: open what looks like a web service, otherwise copy its address.
    private func activate(_ listener: Listener) {
        if let url = store.webURL(for: listener), !store.scanFailed { store.open(url) } else { copyAddress(listener) }
    }

    private func copyAddress(_ listener: Listener) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("\(listener.host):\(listener.port)", forType: .string)
        copiedID = listener.id
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if copiedID == listener.id { copiedID = nil }
        }
    }

    private func requestStop(_ listener: Listener) {
        if store.service(for: listener).container == nil, store.termination[listener.process] == .forceAvailable {
            forceTarget = listener
        } else { store.stop(listener) }
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            if settingsVisible {
                Button { settingsVisible = false } label: { Image(systemName: "chevron.left").frame(width: 22, height: 26) }
                    .buttonStyle(.borderless).help("Back to ports").accessibilityLabel("Back to ports")
                Text("Settings").font(.system(size: 13, weight: .semibold))
            } else {
                BrandLogo(size: 26)
                Text("Yolk").font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            if !settingsVisible { Text(visible.count == store.listeners.count ? String(visible.count) : "\(visible.count)/\(store.listeners.count)")
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: visible.count)
                .help("\(visible.count) visible of \(store.listeners.count) detected ports") }
            Spacer()
            if !settingsVisible { Button {
                searchVisible = true
                DispatchQueue.main.async { searchFocused = true }
            } label: { Image(systemName: "magnifyingglass").frame(width: 24, height: 26) }
                .buttonStyle(.borderless).keyboardShortcut("f")
                .help("Search (⌘F)").accessibilityLabel("Search services")
            optionsMenu
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.55)) { refreshTurns += 1 }
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise").rotationEffect(.degrees(refreshTurns * 360)).frame(width: 24, height: 26)
            }
            .buttonStyle(.borderless).disabled(store.isRefreshing).keyboardShortcut("r")
            .help("Refresh now (⌘R)").accessibilityLabel("Refresh processes")
            }
            Button { settingsVisible.toggle(); searchFocused = false } label: {
                Image(systemName: settingsVisible ? "slider.horizontal.3" : "gearshape").frame(width: 24, height: 26)
            }.buttonStyle(.borderless).keyboardShortcut(",")
                .help("Settings (⌘,)").accessibilityLabel("Settings")
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
    }

    private var optionsMenu: some View {
        Menu {
            Toggle("Favorites only", isOn: $favoritesOnly)
            Toggle("Show hidden services", isOn: $showHidden)
            Toggle("Group by type", isOn: $groupByType)
            if groupByType {
                Button("Expand all") { lastToggledGroup = nil; collapsedGroups = "" }
                Button("Collapse all") {
                    lastToggledGroup = nil
                    collapsedGroups = (["favorites"] + ServiceCategory.allCases.map(\.rawValue)).joined(separator: ",")
                }.disabled(searching)
            }
            if !store.preferences.hidden.isEmpty {
                Menu("Restore hidden (\(store.preferences.hidden.count))") {
                    ForEach(store.preferences.hidden.keys.sorted(), id: \.self) { key in
                        if let saved = store.preferences.hidden[key] {
                            Button("\(saved.title) :\(String(saved.port))") { store.restoreHidden(key: key) }
                        }
                    }
                    Divider()
                    Button("Restore all") { store.restoreAllHidden() }
                }
            }

        } label: {
            Image(systemName: favoritesOnly || showHidden ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
                .foregroundStyle(theme.accent).frame(width: 24, height: 26).contentShape(Rectangle())
        }
        // The borderless menu style ignores the tint, so draw the label as a plain button.
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .help("Filter services").accessibilityLabel("Filter services")
    }

    private var searchBar: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.system(size: 11))
            TextField("Name, port or PID", text: $query)
                .textFieldStyle(.plain).font(.system(size: 12)).focused($searchFocused)
                .accessibilityLabel("Search by name, port or PID")
                .onExitCommand {
                    if !query.isEmpty { query = "" }
                    else { searchVisible = false; searchFocused = false }
                }
            Button {
                if query.isEmpty { searchVisible = false; searchFocused = false }
                else { query = ""; searchFocused = true }
            } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                .buttonStyle(.borderless).help(query.isEmpty ? "Close search" : "Clear search")
                .accessibilityLabel(query.isEmpty ? "Close search" : "Clear search")
        }
        .padding(.horizontal, 9).frame(height: 28)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 14).padding(.bottom, 10)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Color.clear.frame(height: 0).id("list-top")
                    if groupByType {
                        ForEach(groups) { group in
                            Section {
                                if !isCollapsed(group.id) {
                                    ForEach(group.rows) { listener in serviceRow(listener) }
                                }
                            } header: {
                                ServiceGroupHeader(title: group.title, count: group.rows.count,
                                                   collapsed: isCollapsed(group.id), canCollapse: !searching,
                                                   stopAll: group.rows.contains(where: store.canStop) && !store.scanFailed ? { stopAllTarget = group } : nil) {
                                    toggleGroup(group.id)
                                }.id(group.id)
                            }
                        }
                    } else {
                        ForEach(visible) { listener in serviceRow(listener) }
                    }
                }
                .overlayScrollers()
                // Only real arrivals and departures animate; filtering and collapsing stay instant.
                .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: store.listeners.map(\.id))
            }
            .frame(height: listHeight)
            .onChange(of: selection) { id in
                guard navigated, let id else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) { proxy.scrollTo(id, anchor: .center) }
            }
            .onChange(of: query) { _ in proxy.scrollTo("list-top", anchor: .top) }
            .onChange(of: favoritesOnly) { _ in proxy.scrollTo("list-top", anchor: .top) }
            .onChange(of: showHidden) { _ in proxy.scrollTo("list-top", anchor: .top) }
            .onChange(of: groupByType) { _ in proxy.scrollTo("list-top", anchor: .top) }
            .onChange(of: collapsedGroups) { _ in
                DispatchQueue.main.async { proxy.scrollTo(lastToggledGroup ?? "list-top", anchor: .top) }
            }
        }
    }

    private func serviceRow(_ listener: Listener) -> some View {
        ServiceRow(store: store, listener: listener, selected: selection == listener.id, copied: copiedID == listener.id,
                   activate: { activate(listener) }, copy: { copyAddress(listener) }, requestStop: { requestStop(listener) })
            .transition(.opacity)
    }

    private func toggleGroup(_ id: String) {
        guard !searching else { return }
        lastToggledGroup = id
        var collapsed = Set(collapsedGroups.split(separator: ",").map(String.init))
        if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
        collapsedGroups = collapsed.sorted().joined(separator: ",")
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(store.scanFailed ? "List not updated" : "Refreshes every \(settings.refreshSeconds) s")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            if !store.preferences.hidden.isEmpty {
                Button(showHidden ? "Hide again" : "\(store.preferences.hidden.count) hidden") { showHidden.toggle() }
                    .buttonStyle(.borderless).font(.system(size: 10))
            }
            Spacer()
            if login.needsApproval {
                Button { login.openSettings() } label: { Image(systemName: "exclamationmark.circle") }
                    .buttonStyle(.borderless).help("Launch at login needs approval in System Settings")
                    .accessibilityLabel("Allow launch at login")
            }
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q").buttonStyle(.borderless).font(.system(size: 11))
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }

    private func messageBar(_ message: String) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.circle").foregroundStyle(.secondary)
                Text(message).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if !store.scanFailed {
                    Button { store.message = nil; login.error = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless).accessibilityLabel("Dismiss message")
                }
            }.padding(12)
            Divider()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            if !store.hasLoaded {
                ProgressView().controlSize(.small)
                Text("Looking for ports…").font(.system(size: 12))
            } else if store.scanFailed {
                Image(systemName: "exclamationmark.circle").font(.system(size: 22, weight: .light))
                Text("Couldn't scan ports").font(.system(size: 12, weight: .medium))
            } else if searching {
                Image(systemName: "magnifyingglass").font(.system(size: 22, weight: .light))
                Text("No matches").font(.system(size: 12, weight: .medium))
                Button("Clear search") { query = "" }.buttonStyle(.borderless)
            } else if favoritesOnly {
                Image(systemName: "star").font(.system(size: 22, weight: .light))
                Text("No visible favorites").font(.system(size: 12, weight: .medium))
                Button("Show all") { favoritesOnly = false }.buttonStyle(.borderless)
            } else if !store.listeners.isEmpty {
                Image(systemName: "eye.slash").font(.system(size: 22, weight: .light))
                Text("All services are hidden").font(.system(size: 12, weight: .medium))
                Button("Show hidden") { showHidden = true }.buttonStyle(.borderless)
            } else {
                Image(systemName: "checkmark.circle").font(.system(size: 22, weight: .light))
                Text("No listening ports").font(.system(size: 12, weight: .medium))
                Text("Your local servers will show up here.").font(.system(size: 11))
            }
        }
        .foregroundStyle(.secondary).frame(maxWidth: .infinity)
    }
}

private struct ServiceGroupHeader: View {
    let title: String
    let count: Int
    let collapsed: Bool
    let canCollapse: Bool
    let stopAll: (() -> Void)?
    let toggle: () -> Void
    @State private var hovered = false
    @State private var animateChevron = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            Button {
                animateChevron = NSApp.currentEvent?.type == .leftMouseUp || NSApp.currentEvent?.type == .leftMouseDown
                toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold))
                        .rotationEffect(.degrees(collapsed ? 0 : 90)).frame(width: 8)
                        .animation(animateChevron && !reduceMotion ? .easeOut(duration: 0.16) : nil, value: collapsed)
                    Text(title).font(.system(size: 10, weight: .semibold))
                    Text(String(count)).font(.system(size: 9, design: .monospaced)).opacity(0.8)
                    Spacer()
                }
                .foregroundStyle(.secondary).padding(.leading, 16).frame(height: 30).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title), \(count) ports")
            .accessibilityValue(collapsed ? "Collapsed" : "Expanded")
            .help(canCollapse ? (collapsed ? "Show \(title.lowercased())" : "Collapse \(title.lowercased())") : "Results stay visible while searching")
            if hovered, let stopAll {
                Button(role: .destructive, action: stopAll) {
                    Image(systemName: "stop.circle").foregroundStyle(.secondary).frame(width: 24, height: 28)
                }
                .buttonStyle(.borderless).transition(.opacity)
                .help("Stop everything in \(title.lowercased())…").accessibilityLabel("Stop everything in \(title)")
            }
        }
        .padding(.trailing, 16).frame(height: 30)
        .background(ThemeSurface())
        .overlay(Color.primary.opacity(hovered && canCollapse ? 0.035 : 0).allowsHitTesting(false))
        .onHover { hovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
    }
}
