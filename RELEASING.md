# Releasing Yolk

## Source beta

- Confirm the public repository owner and author attribution in LICENSE.
- Inspect the source and history for credentials, local paths, personal data and unlicensed assets. Publish the source directory, not the enclosing workspace or build cache.
- Enable GitHub private vulnerability reporting.
- Verify CI on the repository. The supplied workflow performs tests and universal packaging; it has not been run on GitHub merely by being present in the source.
- Update Info.plist version/build, CHANGELOG.md and screenshots.
- Create a version tag, for example `v1.4.0-beta.1`, only after reviewing the exact commit.
- A source-only beta can be published without a Developer ID. Label local/CI binaries as development builds, not notarized releases.

## Downloadable public app

A public notarized package requires an Apple Developer ID Application signing identity and a configured notarytool keychain profile. Do not commit certificates, passwords or API keys. Use Apple's documented credential setup on the maintainer's Mac.

```sh
YOLK_SIGN_IDENTITY='Developer ID Application: Your identity (TEAMID)' \
YOLK_NOTARY_PROFILE='your-saved-profile' \
bash scripts/release.sh
```

The script builds a universal app, signs with hardened runtime, submits to Apple, waits for acceptance, staples the ticket, checks Gatekeeper and produces a versioned ZIP and SHA-256 file. It stops on any failure. Submission and signing require real credentials and cannot be validated by the unsigned local build. This script does not upload a GitHub release.

Upload the resulting ZIP and checksum to a GitHub prerelease and include the supported/tested systems and known limitations. Keep release drafts until the downloaded, quarantined artifact has been verified on a clean Mac. A README checkmark is not evidence of notarization.

## Manual validation before promoting a beta

- Install the downloaded package and open it on Apple Silicon and Intel; verify signature and Gatekeeper behavior.
- Check the oldest supported macOS and the newest supported release.
- Confirm there is no Dock icon and opening a second copy does not duplicate the menu item.
- Open, close, search, scroll and repeatedly collapse groups in the actual menu-bar panel.
- Check multi-monitor placement, display scaling, light/dark and every palette.
- Test keyboard navigation, VoiceOver, Reduce Motion and Reduce Transparency.
- Verify settings persistence and migration from Local Ports, including hidden services and favorites.
- Enable/disable login on an installed copy and test a real login. The automated tests use a fake service.
- Verify normal/forced termination using disposable processes only.
- Check idle CPU/energy use and responsive behavior with many listeners.
- A universal binary being produced does not mean both architectures have been runtime-tested.

## Identity continuity

The visible name is Yolk (earlier builds were called Local Ports and Port Dog). The bundle ID remains `local.localports.app` so existing preferences and duplicate-instance detection work. Internal module names remain LocalPorts to minimize migration risk. A future bundle-ID change must include preference migration and cleanup/re-registration of login items; do not silently change it just to match a new repository owner.
