# Beta validation — 1.4.0

Verified locally on macOS 27.0.1, Apple Silicon, with Xcode Command Line Tools:

- 49 automated tests passed (35 core, 14 application).
- Universal release build contains arm64 and x86_64 slices.
- Ad-hoc signature verifies; the application icon is embedded.
- Actual SwiftUI views rendered in native offscreen windows: list, settings, every palette's logo in light and dark, and light mode while the system is dark.
- Keyboard handling (arrow selection, copy, type-to-search) driven with synthetic key events in an offscreen window.
- In the real menu-bar host: the panel opens and closes through the path the global shortcut uses, panel visibility is tracked, and the new-port dot turns on when a disposable local server starts and clears when the panel opens.
- Container support exercised against a fake engine socket, including the stop request and rejection of malformed identifiers.
- The logo drawn by the app matches `Brand/logo.svg` pixel for pixel at 512 px.
- Shell scripts and workflow YAML pass syntax checks, and the GitHub Actions workflow (tests plus universal build) passes on a hosted macOS runner.
- Source scan found no home-directory paths or common credential/private-key patterns. This is a targeted check, not a comprehensive security audit.

Not yet verified by a person or on real hardware:

- Animations, hover behavior and the look of the menu bar symbol in an actual menu bar.
- Pressing a recorded global shortcut, and the shortcut recorder itself.
- A running Docker, OrbStack, Colima or Rancher Desktop engine.
- The "stop everything" confirmation and opening projects in editors and terminals.
- macOS 13 to 26: the global shortcut uses a different code path there than on macOS 27.

Still requires validation before a general public binary release:

- Developer ID signing, Apple notarization and installation of a quarantined download.
- Runtime testing on Intel and older supported macOS releases.
- Live menu-bar interactions across display arrangements and accessibility settings.
- Real launch-at-login cycle; automated coverage uses a fake backend.

The screenshots contain sample services. Offscreen view tests are not a substitute for the real menu-bar host checks in RELEASING.md.
