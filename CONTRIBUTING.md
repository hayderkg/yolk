# Contributing

Yolk should stay small, native and easy to understand. Please open an issue describing the problem before starting a large feature. Small focused pull requests are welcome.

## Setup

Use macOS 13+ and Xcode or Command Line Tools with Swift 5.9+. Open `Package.swift` in Xcode, or use `swift test` and `bash scripts/build.sh` from the repository root. There are no external package dependencies.

## Changes

- Describe the user-visible problem and resulting behavior.
- Add meaningful tests for process control, persistence and parsing changes.
- Keep signal ownership/creation-time checks and force-kill confirmation intact.
- Network requests for icons must remain bounded and restricted to the same local origin.
- Keep keyboard actions immediate; respect Reduce Motion and Reduce Transparency.
- For UI changes, check light/dark, all palettes, empty/search/collapsed states, pinned headers, keyboard focus and VoiceOver labels.
- Run `swift test` and build the app. Report untested environments honestly.
- Remove private project paths and names from screenshots or logs.

Contributions are accepted under the repository's MIT license. Do not add copied brand artwork or dependencies with incompatible licensing. Security-sensitive reports should follow `SECURITY.md`.
