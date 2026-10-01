# Physical-device performance evidence

> **Sign-off status: PENDING** — a dated physical-device measurement is
> required before release. No synthetic or Simulator result may be recorded
> here. This file is the release gate and fails closed until every placeholder
> below is replaced with a real device measurement.

This record is consumed by `scripts/check_device_signoff.sh`. The gate exits
non-zero while the sign-off date is unrecorded or any field below still
carries the placeholder token.

Procedure and thresholds: see [Performance device sign-off](performance-device-signoff.md).

<!-- SIGN_OFF_DATE: PENDING -->
<!-- DEVICE_MODEL: PENDING -->
<!-- IOS_VERSION: PENDING -->
<!-- BUILD_COMMIT: PENDING -->

## Measurement record (minimum device: A17 Pro-class iPhone, 8 GB RAM, Release build)

| Metric | Threshold | Measured | Result |
| --- | --- | --- | --- |
| Sustained FPS (full race) | >= 55 | PENDING | PENDING |
| Frame time p95 | <= 16.67 ms | PENDING | PENDING |
| CPU simulation p95 | <= 2 ms/frame | PENDING | PENDING |
| Render submission p95 | <= 5 ms/frame | PENDING | PENDING |
| GPU p95 | <= 8 ms/frame | PENDING | PENDING |
| Recursive nodes (medium tier) | <= 650 | PENDING | PENDING |
| Geometry/draw-ish nodes (medium tier) | <= 420 | PENDING | PENDING |
| Road chunks (medium tier) | 14 | PENDING | PENDING |
| Resident memory | < 650 MB | PENDING | PENDING |
| Retry-loop memory growth | no sustained growth | PENDING | PENDING |
| Transient allocation | < 5 MB/s | PENDING | PENDING |
| Title-to-race load time | < 3 s | PENDING | PENDING |
| Thermal state | <= `.fair` | PENDING | PENDING |

When the owner device run completes: set `Sign-off status` to `RECORDED`,
replace the four marker placeholders above (using a valid ISO `YYYY-MM-DD`
date for `SIGN_OFF_DATE`; each marker must appear exactly once), and fill
every `Measured` cell with the real measurement (numeric with its unit,
e.g. `58.4 fps` or `480 MB`; `none`/`stable` for retry-loop growth;
`nominal`/`fair` for thermal) and set every `Result` cell to `PASS`.
The gate passes only when all four markers are unique and filled, the date
is a valid calendar date, no placeholder token remains anywhere in this
file, and every required metric row appears exactly once with the checklist
threshold intact, a plausible measurement inside its budget, and an exact
`PASS` verdict. Editing a threshold, blanking a measurement, recording a
non-`PASS` verdict, or adding/removing rows keeps the gate closed. The
gate validates the record's completeness and consistency; the authenticity
of the underlying device run remains the signatory's accountability.
