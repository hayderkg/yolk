import AppKit
import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    enum Appearance: String, CaseIterable { case system, light, dark
        var title: String { switch self { case .system: return "System"; case .light: return "Light"; case .dark: return "Dark" } }
        var colorScheme: ColorScheme? { switch self { case .system: return nil; case .light: return .light; case .dark: return .dark } }
    }
    enum Palette: String, CaseIterable { case native, mustard, bubblegum, electric
        var title: String { self == .native ? "Native" : rawValue.capitalized }
    }
    enum Surface: String, CaseIterable { case translucent, solid
        var title: String { self == .translucent ? "Translucent" : "Solid" }
    }
    static let refreshOptions = [2, 3, 5, 10]
    private let defaults: UserDefaults
    @Published var appearance: Appearance { didSet { defaults.set(appearance.rawValue, forKey: "appearance") } }
    @Published var palette: Palette { didSet { defaults.set(palette.rawValue, forKey: "palette") } }
    @Published var surface: Surface { didSet { defaults.set(surface.rawValue, forKey: "surface") } }
    @Published private(set) var refreshSeconds: Int
    @Published var newPortDot: Bool { didSet { defaults.set(newPortDot, forKey: "newPortDot") } }
    @Published var hotKey: HotKey? { didSet { defaults.set(hotKey.flatMap { try? JSONEncoder().encode($0) }, forKey: "hotKey") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = Appearance(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
        palette = Palette(rawValue: defaults.string(forKey: "palette") ?? "") ?? .native
        surface = Surface(rawValue: defaults.string(forKey: "surface") ?? "") ?? .translucent
        let interval = defaults.integer(forKey: "refreshSeconds")
        refreshSeconds = Self.refreshOptions.contains(interval) ? interval : 3
        newPortDot = defaults.object(forKey: "newPortDot") as? Bool ?? true
        hotKey = defaults.data(forKey: "hotKey").flatMap { try? JSONDecoder().decode(HotKey.self, from: $0) }
    }

    func setRefreshSeconds(_ value: Int) {
        guard Self.refreshOptions.contains(value) else { return }
        refreshSeconds = value
        defaults.set(value, forKey: "refreshSeconds")
    }

    func resetAppearance() { appearance = .system; palette = .native; surface = .translucent }
}

struct PortTheme {
    var palette: AppSettings.Palette = .native
    var dark = false
    var translucent = true

    var accent: Color {
        switch palette {
        case .native: return .accentColor
        case .mustard: return dark ? Color(hex: 0xFFD166) : Color(hex: 0x8C4900)
        case .bubblegum: return dark ? Color(hex: 0xFF9ED9) : Color(hex: 0xA31B66)
        case .electric: return dark ? Color(hex: 0xDCFA62) : Color(hex: 0x244EE5)
        }
    }
    var paper: Color {
        switch palette {
        case .native: return dark ? Color(hex: 0x242426) : Color(hex: 0xF5F5F7)
        case .mustard: return Color(hex: dark ? 0x2D251C : 0xFFF5DD)
        case .bubblegum: return Color(hex: dark ? 0x302333 : 0xFFF0F8)
        case .electric: return Color(hex: dark ? 0x192343 : 0xEEF1FF)
        }
    }
    var logoTile: Color {
        switch palette {
        case .native: return Color(hex: dark ? 0x3A3A3D : 0xFFFFFF)
        case .mustard, .bubblegum, .electric: return swatch
        }
    }
    var logoInk: Color {
        switch palette {
        case .native: return Color(hex: dark ? 0xF5F5F7 : 0x1D1D1F)
        case .mustard: return Color(hex: 0x2D251C)
        case .bubblegum: return Color(hex: 0x302333)
        case .electric: return .white
        }
    }
    var logoYolk: Color {
        switch palette {
        case .native: return Color(hex: 0xFFC61A)
        case .mustard: return Color(hex: 0xFFF5DD)
        case .bubblegum: return Color(hex: 0x8ADBD0)
        case .electric: return Color(hex: 0xE1F76A)
        }
    }
    var swatch: Color {
        switch palette {
        case .native: return Color(hex: 0xA6ACB6)
        case .mustard: return Color(hex: 0xF4B83F)
        case .bubblegum: return Color(hex: 0xF587CF)
        case .electric: return Color(hex: 0x4369FF)
        }
    }
}

private struct PortThemeKey: EnvironmentKey { static let defaultValue = PortTheme() }
extension EnvironmentValues {
    var portTheme: PortTheme { get { self[PortThemeKey.self] } set { self[PortThemeKey.self] = newValue } }
}
extension Color {
    init(hex: UInt32) { self.init(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255) }
}

struct ThemeSurface: View {
    @Environment(\.portTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        if theme.translucent && !reduceTransparency {
            Rectangle().fill(.regularMaterial)
                .overlay(theme.palette == .native ? Color.clear : theme.paper.opacity(0.55))
        } else { theme.paper }
    }
}

/// Pins the hosting window to the chosen appearance. `preferredColorScheme` alone does not
/// reach the MenuBarExtra window, leaving text and AppKit controls in the system appearance.
struct WindowAppearance: NSViewRepresentable {
    let colorScheme: ColorScheme?
    func makeNSView(context: Context) -> ProbeView { ProbeView() }
    func updateNSView(_ view: ProbeView, context: Context) {
        view.colorScheme = colorScheme
        view.apply()
    }

    final class ProbeView: NSView {
        var colorScheme: ColorScheme?
        private var observation: NSKeyValueObservation?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Reapply if the system or SwiftUI swaps the appearance behind our back.
            observation = window?.observe(\.effectiveAppearance) { [weak self] _, _ in
                DispatchQueue.main.async { self?.apply() }
            }
            apply()
        }

        func apply() {
            guard let window else { return }
            let name: NSAppearance.Name? = colorScheme.map { $0 == .dark ? .darkAqua : .aqua }
            guard window.appearance?.name != name else { return }
            window.appearance = name.flatMap(NSAppearance.init(named:))
        }
    }
}
