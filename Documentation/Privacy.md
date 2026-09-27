# Privacy review

## Current behavior

As of this review, Neon Racer:

- performs no tracking and does not request App Tracking Transparency authorization;
- contains no advertising, analytics, third-party SDK, account, network, or web-view code;
- does not collect or transmit personal data;
- stores a local gameplay profile (best score and selected vehicle ID) in Application Support;
- stores user-selected audio and accessibility preferences in the app's own `UserDefaults`;
- uses local audio and haptic frameworks without collecting data.

`NeonRacer/Resources/PrivacyInfo.xcprivacy` therefore declares no tracking, collected data types, or tracking domains. It declares Apple's `CA92.1` required reason for reading and writing preferences that are accessible only to this app. The manifest is included in the app target's Copy Bundle Resources phase.

## App Store privacy answers

For the current binary, select **Data Not Collected** and indicate that the app does not use data for tracking. These answers describe the shipped binary, not future intent.

## Review required before every submission

Search first-party and dependency code for networking, analytics, ads, accounts, cloud saves, crash reporting, pasteboard, preferences, file timestamp, disk-space, or system-uptime APIs. Review Apple's current required-reason API list and every third-party SDK privacy manifest. If behavior changes:

1. update the manifest and this document;
2. update App Store Connect privacy answers;
3. obtain approval before adding analytics, advertising, fingerprinting, or tracking;
4. provide any needed consent, deletion, retention, and privacy-policy flows.

Local profile deletion currently follows normal app deletion. If in-app account or cloud data is introduced, add an in-app deletion path and document retention.

## Public privacy policy draft

Publish an owner-approved policy at a stable HTTPS URL before submission:

> Neon Racer does not collect, transmit, sell, or share personal data. Gameplay progress is stored only on your device and is removed when you delete the app. The app does not contain advertising or analytics and does not track you across apps or websites. For privacy questions, contact [SUPPORT EMAIL].

Replace the placeholder, add an effective date and legal owner, and have the owner review the policy. The repository document is not itself a public privacy-policy URL.
