import SwiftUI

enum AppInfo {
    /// Read from the bundle; unbundled runs (`swift run`, tests) fall back to the current release.
    static let version = Bundle.main.bundleIdentifier == "local.localports.app"
        ? Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.4.0" : "1.4.0"
}

struct SettingsPanel: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var login: LoginItemController
    @Environment(\.portTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    BrandLogo(size: 76)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Localhost, sunny side up.").font(.system(size: 16, weight: .bold, design: .rounded))
                        Text("Your servers, close at hand.").font(.system(size: 11)).foregroundStyle(.secondary)
                        Text("Yolk · \(AppInfo.version) beta")
                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
                section("APPEARANCE") {
                    Picker("Mode", selection: $settings.appearance) {
                        ForEach(AppSettings.Appearance.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden().accessibilityLabel("Appearance mode")
                    HStack(spacing: 8) {
                        ForEach(AppSettings.Palette.allCases, id: \.self) { palette in
                            paletteButton(palette)
                        }
                    }
                    Picker("Background", selection: $settings.surface) {
                        ForEach(AppSettings.Surface.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden().accessibilityLabel("Panel background")
                    Text("Transparency follows your Mac's accessibility settings.")
                        .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                section("BEHAVIOR") {
                    HStack {
                        Text("Refresh every").font(.system(size: 12))
                        Spacer()
                        Picker("Refresh interval", selection: Binding(get: { settings.refreshSeconds }, set: settings.setRefreshSeconds)) {
                            ForEach(AppSettings.refreshOptions, id: \.self) { Text("\($0) s").tag($0) }
                        }.labelsHidden().frame(width: 84)
                    }
                    HStack {
                        Text("Global shortcut").font(.system(size: 12))
                        Spacer()
                        ShortcutRecorder(hotKey: $settings.hotKey)
                    }
                    Toggle("Dot on the menu bar icon for new ports", isOn: $settings.newPortDot)
                        .toggleStyle(.switch).controlSize(.small).font(.system(size: 12))
                    Toggle("Launch at login", isOn: Binding(get: { login.isRegistered }, set: { enabled in Task { await login.setEnabled(enabled) } }))
                        .toggleStyle(.switch).controlSize(.small).font(.system(size: 12)).disabled(login.isUpdating)
                    if login.needsApproval {
                        Button("Allow in System Settings…") { login.openSettings() }.buttonStyle(.borderless)
                    }
                }
                HStack {
                    Text("Open source · MIT").font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset appearance") { settings.resetAppearance() }
                        .buttonStyle(.borderless).font(.system(size: 10))
                }
            }.padding(18).overlayScrollers()
        }.frame(height: 502)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 9, weight: .semibold)).tracking(0.9).foregroundStyle(.secondary)
            content()
        }
    }

    private func paletteButton(_ palette: AppSettings.Palette) -> some View {
        let selected = settings.palette == palette
        let swatch = PortTheme(palette: palette).swatch
        return Button { settings.palette = palette } label: {
            VStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 6).fill(swatch)
                    .overlay(alignment: .bottomTrailing) {
                        Circle().fill(palette == .bubblegum ? Color(hex: 0x8ADBD0) : palette == .electric ? Color(hex: 0xE1F76A) : .white.opacity(0.7))
                            .frame(width: 13, height: 13).padding(5)
                    }.frame(height: 32)
                Text(palette.title).font(.system(size: 10, weight: selected ? .semibold : .regular)).lineLimit(1)
            }
            .padding(6).frame(maxWidth: .infinity)
            .background(theme.accent.opacity(selected ? 0.1 : 0), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(selected ? theme.accent : .primary.opacity(0.1), lineWidth: selected ? 1.5 : 0.5))
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain).accessibilityLabel("\(palette.title) palette")
            .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// Captures the next key combination as the global shortcut. Escape cancels.
private struct ShortcutRecorder: View {
    @Binding var hotKey: HotKey?
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 4) {
            Button(recording ? "Type shortcut…" : hotKey?.display ?? "Record…") { recording ? stop() : start() }
                .controlSize(.small).accessibilityLabel(hotKey.map { "Global shortcut \($0.display). Record a new one" } ?? "Record global shortcut")
                .help("Opens Yolk from anywhere. Needs ⌘, ⌥ or ⌃.")
            if hotKey != nil && !recording {
                Button { hotKey = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.borderless).help("Remove shortcut").accessibilityLabel("Remove global shortcut")
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil }
            guard let recorded = HotKey(event: event) else { NSSound.beep(); return nil }
            hotKey = recorded
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
