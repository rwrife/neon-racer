# Release and archive runbook

## Build contract

- Project: `NeonRacer.xcodeproj`
- Shared scheme: `NeonRacer`
- App bundle ID: `com.infinityball.neonracer`
- Minimum OS: iOS 26.0; iPhone only
- CI toolchain: Xcode 26.0.1 (`17A400`) and the iOS 26.0 SDK on GitHub's `macos-15` image
- Version source: `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in the app target

CI deliberately sets `DEVELOPER_DIR=/Applications/Xcode_26.0.1.app/Contents/Developer` and fails if either the Xcode version, build number, or simulator SDK differs. Before changing the pin, confirm the replacement in GitHub's `actions/runner-images` macOS software list and update the version, build number, SDK check, and README together.

## Signing

Keep automatic signing enabled. A release operator must select the owner's Apple Developer team locally or through an approved, access-controlled CI system. Never commit certificates, private keys, provisioning profiles, App Store Connect API keys, passwords, a filled-in team ID, or developer-specific Xcode user data.

The committed project intentionally has an empty `DEVELOPMENT_TEAM`. Bundle IDs must exist in the owner's Apple Developer account before archiving. Test targets use `.tests` and `.uitests` suffixes.

## Versioning

- Set `MARKETING_VERSION` to the user-visible semantic version, for example `1.0.0`.
- Increment `CURRENT_PROJECT_VERSION` for every App Store Connect upload. Never reuse a build number for the same marketing version.
- Record the released commit, marketing version, build number, and App Store Connect status in the GitHub release.
- A rollback is a new build: revert or fix the offending commit, increment the build number, test, and upload. App Store binaries are immutable.

Example without editing the project:

```sh
VERSION=1.0.0
BUILD_NUMBER=42
```

Pass both values to the archive command below. Release builds use Xcode's Release configuration and whole-module optimization defaults; verify effective settings with `xcodebuild -showBuildSettings -configuration Release`.

## Clean archive

From a clean clone with Xcode 26.0.1 selected:

```sh
git status --short # must print nothing
export DEVELOPER_DIR=/Applications/Xcode_26.0.1.app/Contents/Developer
VERSION=1.0.0
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

1. CI passes at the exact release commit.
2. Privacy review, asset provenance, IP review, metadata, and TestFlight checklist are signed off.
3. Archive validation reports no missing icons, privacy manifest, signing, or entitlement errors.
4. Exported artifact version and build match the release record.
5. Upload to TestFlight, complete smoke testing, then submit with owner approval.
