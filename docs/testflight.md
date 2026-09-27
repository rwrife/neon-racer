# TestFlight smoke, rollout, and rollback checklist

Record device, OS, build number, tester, date, and result for each run. Test at least the oldest supported iPhone class available to the team and a current flagship device.

## Install and lifecycle

- [ ] Fresh TestFlight install launches without crash, blank screen, or network dependency.
- [ ] Upgrade from the previous TestFlight build preserves compatible local progress.
- [ ] Full race can be started, played, completed, restarted, and exited.
- [ ] Pause/resume works; gameplay time does not jump after pausing.
- [ ] Home/background/foreground, screen lock, phone/audio interruption, and low-memory recovery are acceptable.
- [ ] Force-quit and relaunch preserve intended settings and progress.

## Input, media, and access

- [ ] Touch controls work at all supported iPhone sizes and landscape orientations.
- [ ] Connected controller behavior is tested, or store metadata clearly says controller support is absent.
- [ ] Audio starts/stops cleanly, respects output changes, and behaves acceptably with silent mode and other audio.
- [ ] Haptics work on supported hardware and degrade safely when unavailable or disabled.
- [ ] VoiceOver labels and focus order are usable; larger text, Increase Contrast, Reduce Motion, and Reduce Transparency are reviewed.
- [ ] Important state is not conveyed by color alone and contrast is readable.

## Settings, save, and privacy

- [ ] Audio/accessibility settings persist after relaunch and can be reset as designed.
- [ ] Local best score/progress persists across relaunch and compatible upgrades.
- [ ] App deletion removes local data as expected.
- [ ] Airplane-mode behavior confirms the app has no unexpected network dependency.
- [ ] Privacy report/traffic inspection shows no unexpected domains or data transfer.

## Performance and release integrity

- [ ] Sustained full run on the minimum device has acceptable frame pacing, thermals, memory, battery, and loading time.
- [ ] No debug overlays, placeholder copy/art, test accounts, private endpoints, or development-only launch arguments appear.
- [ ] App icon, display name, version/build, launch presentation, and orientation are correct.
- [ ] App Store screenshots and description match this exact build.
- [ ] Crash and feedback reports are reviewed and all release blockers resolved.

## Rollout and rollback

Use internal testers first, then a small external group before broad TestFlight distribution or phased App Store release. Keep the previous approved version available where App Store Connect permits.

If a blocker appears:

1. Stop external testing or pause the phased release.
2. Document affected versions, devices, reproduction steps, and user impact.
3. Fix forward or revert the offending commit.
4. Increment `CURRENT_PROJECT_VERSION`; do not reuse the failed build number.
5. Rerun CI, archive validation, and this smoke checklist.
6. Upload a new immutable build and notify testers/reviewers of the replacement.
