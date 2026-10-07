# Release and archive runbook

## Build contract

- Project: `NeonRacer.xcodeproj`
- Shared scheme: `NeonRacer`
- App bundle ID: `com.infinityball.neon-racer`
- Display name: `CyberRun`; marketing version: `1.0`
- Minimum OS: iOS 26.0; iPhone and iPad; landscape left/right
- CI runner/toolchain: GitHub Actions `macos-26`, Xcode 26.6 (`17F113`), iOS Simulator SDK 26.5
- Version source: `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in the app target

The CI workflow deliberately selects `/Applications/Xcode_26.6.app/Contents/Developer` with `xcode-select` and fails if the Xcode version, build number, or simulator SDK drifts. This pin was checked against GitHub's `actions/runner-images` macOS 26 image documentation on 2026-09-26. Before changing it, confirm the replacement Xcode and iOS SDK are installed on the chosen runner image, then update `.github/workflows/ci.yml`, this file, and `README.md` together.

## Signing and secrets

Keep automatic signing enabled. A release operator must select the owner's Apple Developer team locally or through an approved, access-controlled release system. Never commit certificates, private keys, provisioning profiles, App Store Connect API keys, passwords, filled-in team IDs, export passwords, or developer-specific Xcode user data.

The committed project intentionally has an empty `DEVELOPMENT_TEAM`. Bundle IDs must exist in the owner's Apple Developer account before archiving. Test targets use `.tests` and `.uitests` suffixes.

## Version and build numbering

- `MARKETING_VERSION` is the user-visible version, currently `1.0`.
- `CURRENT_PROJECT_VERSION` is the monotonically increasing App Store Connect build number.
- Increment `CURRENT_PROJECT_VERSION` for every upload; never reuse a build number for the same marketing version.
- Record the released commit, marketing version, build number, CI run, TestFlight status, and App Store status in the GitHub release or release issue.
- A rollback is a new build: revert or fix the offending commit, increment the build number, rerun CI and smoke tests, and upload a replacement because App Store binaries are immutable.

Example values used by the commands below:

```sh
VERSION=1.0
BUILD_NUMBER=42
```

## Clean clone archive/export process

From a clean clone with Xcode 26.6 installed and the owner-approved signing account available:

```sh
git status --short # must print nothing
export DEVELOPER_DIR=/Applications/Xcode_26.6.app/Contents/Developer
sudo xcode-select -s "$DEVELOPER_DIR"
VERSION=1.0
BUILD_NUMBER=42
rm -rf build/NeonRacer.xcarchive build/AppStore
xcodebuild archive \
  -project NeonRacer.xcodeproj \
  -scheme NeonRacer \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$PWD/build/NeonRacer.xcarchive" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER"
xcodebuild -exportArchive \
  -archivePath "$PWD/build/NeonRacer.xcarchive" \
  -exportPath "$PWD/build/AppStore" \
  -exportOptionsPlist Config/ExportOptions-AppStore.plist
```

The operator must be signed into Xcode and authorized for the selected team. Prefer Xcode Organizer for the first upload so signing and App Store validation errors are visible. Do not use `-allowProvisioningUpdates` in shared automation unless the credential owner explicitly approves it.

## Release gate

1. CI passes at the exact release commit: `xcrun swift test --quiet`, `xcodebuild build-for-testing`, unit tests, selected UI smoke test, and `xcodebuild analyze`.
2. App icon, launch presentation, privacy manifest, export options, and bundle identity validate.
3. Privacy review, asset provenance, IP review, App Store metadata, screenshot plan, and TestFlight checklist are signed off.
4. Archive validation reports no missing icons, privacy manifest, signing, entitlement, or SDK errors.
5. Exported artifact version/build match the release record.
6. Physical-device performance sign-off passes: follow `docs/performance-device-signoff.md`, record the measurement in `docs/performance-device-evidence.md`, and confirm `bash scripts/check_device_signoff.sh` exits 0. Until a dated device run exists, this gate fails closed and release must not proceed.
7. Upload to TestFlight, complete smoke testing, then submit with explicit owner approval.
