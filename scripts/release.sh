#!/bin/bash
# Run on the maintainer's Mac after setting up a Developer ID and notarytool profile.
set -euo pipefail
: "${YOLK_SIGN_IDENTITY:?Set YOLK_SIGN_IDENTITY to your Developer ID Application identity}"
: "${YOLK_NOTARY_PROFILE:?Set YOLK_NOTARY_PROFILE to a saved notarytool keychain profile}"
if [[ "$YOLK_SIGN_IDENTITY" == "-" ]]; then printf 'A Developer ID identity is required.\n' >&2; exit 1; fi
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export LOCALPORTS_OUTPUT_DIR="${LOCALPORTS_OUTPUT_DIR:-$PROJECT_ROOT/dist}"
export YOLK_UNIVERSAL=1
bash "$PROJECT_ROOT/scripts/build.sh"
APP="$LOCALPORTS_OUTPUT_DIR/Yolk.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
SUBMISSION="$LOCALPORTS_OUTPUT_DIR/Yolk-notary-submission.zip"
ARCHIVE="$LOCALPORTS_OUTPUT_DIR/Yolk-$VERSION-universal.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$SUBMISSION"
xcrun notarytool submit "$SUBMISSION" --keychain-profile "$YOLK_NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"
(cd "$LOCALPORTS_OUTPUT_DIR" && shasum -a 256 "$(basename "$ARCHIVE")" > "$(basename "$ARCHIVE").sha256")
printf '\nNotarized release ready: %s\n' "$ARCHIVE"
