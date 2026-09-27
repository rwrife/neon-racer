# Privacy review

## Current behavior

As of this review, Neon Racer:

- performs no tracking and does not request App Tracking Transparency authorization;
- contains no advertising, analytics, third-party SDK, account, networking, cloud sync, or web-view code;
- does not collect, transmit, sell, or share personal data;
- stores a local gameplay profile in the app's Application Support container;
- stores user-selected audio and accessibility preferences in the app's own `UserDefaults`;
- uses local audio, haptics, SwiftUI, and SceneKit without collecting data.

## Required-reason API audit

Actual first-party usage was checked with source search for `UserDefaults`, `FileManager`, file timestamp/resource-value APIs, system uptime, disk-space APIs, pasteboard, networking, analytics, and tracking frameworks.

| API category | Current use | Manifest entry |
| --- | --- | --- |
| `NSPrivacyAccessedAPICategoryUserDefaults` | App-only settings for audio/accessibility and test-isolated defaults | `CA92.1` |
| File timestamp APIs | No app code reads file creation/modification timestamps or file metadata timestamps | None |
| System boot time APIs | No uptime/boot-time fingerprinting APIs used | None |
| Disk-space APIs | No disk-space fingerprinting APIs used | None |
| Active keyboard APIs | Not used | None |

`NeonRacer/Resources/PrivacyInfo.xcprivacy` declares no tracking, collected data types, or tracking domains. It declares only the `CA92.1` required reason for reading/writing app-only preferences and is included in the app target's Copy Bundle Resources phase.

## App Store privacy answers

For the current binary, answer **Data Not Collected** and indicate that the app does not use data for tracking. These answers describe the shipped binary only; update them before submission if networking, analytics, ads, accounts, cloud saves, crash reporting, or third-party SDK behavior changes.

## Review before every submission

1. Re-run source/dependency searches for networking, analytics, ads, accounts, cloud saves, crash reporting, pasteboard, preferences, file timestamp, disk-space, system-uptime, or fingerprinting APIs.
2. Review Apple's current required-reason API list and every third-party SDK privacy manifest.
3. Update `PrivacyInfo.xcprivacy`, this document, and App Store Connect privacy answers for any behavior change.
4. Obtain owner approval before adding analytics, advertising, fingerprinting, tracking, or off-device data transfer.
5. Add consent, deletion, retention, and privacy-policy flows if account or cloud data is introduced.

Local profile deletion currently follows normal app deletion.

## Public privacy policy draft

Publish an owner-approved policy at a stable HTTPS URL before submission:

> Neon Racer does not collect, transmit, sell, or share personal data. Gameplay progress is stored only on your device and is removed when you delete the app. The app does not contain advertising or analytics and does not track you across apps or websites. For privacy questions, contact [SUPPORT EMAIL].

Replace placeholders, add effective date/legal owner, and have the owner review the policy. This repository document is not itself a public privacy-policy URL.
