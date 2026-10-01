#!/usr/bin/env bash
# Physical-device performance sign-off gate (issue #37).
#
# Fails CLOSED (non-zero) unless docs/performance-device-evidence.md records a
# complete owner sign-off:
#   * all four metadata markers present with non-empty, non-PENDING values;
#   * SIGN_OFF_DATE is a real ISO calendar date (pure bash, no GNU date);
#   * zero PENDING placeholder tokens anywhere in the record;
#   * the measurement table contains every required metric row exactly once,
#     each with a non-empty Measured value and an exact PASS verdict.
# The evidence record currently encodes "PENDING — owner physical-device run
# not yet completed", so release readiness stays blocked until real device
# measurements are recorded. The gate NEVER synthesizes a pass and this
# script must not be weakened to fake one.
set -euo pipefail

cd "$(dirname "$0")/.."

EVIDENCE="docs/performance-device-evidence.md"

if [[ ! -f "$EVIDENCE" ]]; then
    echo "release gate: BLOCKED — $EVIDENCE not found"
    exit 1
fi

marker_value() {
    # Echoes the trimmed value of "<!-- NAME: value -->", or nothing if absent.
    local name="$1"
    grep -m1 -oE "<!-- ${name}:[^>]*-->" "$EVIDENCE" \
        | sed -E "s/^<!-- ${name}:[[:space:]]*//; s/[[:space:]]*-->\$//" \
        || true
}

for marker in SIGN_OFF_DATE DEVICE_MODEL IOS_VERSION BUILD_COMMIT; do
    value="$(marker_value "$marker")"
    if [[ -z "$value" ]]; then
        echo "release gate: BLOCKED — $marker marker is missing"
        exit 1
    fi
    if [[ "$value" == "PENDING" ]]; then
        echo "release gate: BLOCKED — $marker still PENDING"
        exit 1
    fi
done

signoff_date="$(marker_value SIGN_OFF_DATE)"
if ! [[ "$signoff_date" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})$ ]]; then
    echo "release gate: BLOCKED — SIGN_OFF_DATE '$signoff_date' is not an ISO date (YYYY-MM-DD)"
    exit 1
fi
# Calendar validity without GNU date (pure bash, identical on macOS/Linux).
_year=$((10#${BASH_REMATCH[1]}))
_month=$((10#${BASH_REMATCH[2]}))
_day=$((10#${BASH_REMATCH[3]}))
_days_in_month=(31 28 31 30 31 30 31 31 30 31 30 31)
if (( (_year % 4 == 0 && _year % 100 != 0) || _year % 400 == 0 )); then
    _days_in_month[1]=29
fi
if (( _month < 1 || _month > 12 || _day < 1 || _day > _days_in_month[_month - 1] )); then
    echo "release gate: BLOCKED — SIGN_OFF_DATE '$signoff_date' is not a valid calendar date"
    exit 1
fi

pending_cells="$(grep -c 'PENDING' "$EVIDENCE" || true)"
if [[ "$pending_cells" -ne 0 ]]; then
    echo "release gate: BLOCKED — $pending_cells sign-off field(s) still PENDING"
    exit 1
fi

# Measurement table validation: every required metric row exactly once, each
# with a non-empty Measured cell and an EXACT PASS verdict. Unexpected extra
# rows, empty measurements, and non-PASS verdicts (FAIL, blank, FAILPASS, or
# a duplicate PASS masking a failing row) keep the gate closed.
required="Sustained FPS (full race);Frame time p95;CPU simulation p95;Render submission p95;GPU p95;Recursive nodes (medium tier);Geometry/draw-ish nodes (medium tier);Road chunks (medium tier);Resident memory;Retry-loop memory growth;Transient allocation;Title-to-race load time;Thermal state"

if ! awk -F'|' -v required="$required" '
BEGIN {
    n = split(required, req, ";")
    for (i = 1; i <= n; i++) want[req[i]] = 0
}
/^[ \t]*\|/ {
    tables++
    f2 = $2; f3 = $3; f4 = $4; f5 = $5
    gsub(/^[ \t]+|[ \t]+$/, "", f2)
    gsub(/^[ \t]+|[ \t]+$/, "", f3)
    gsub(/^[ \t]+|[ \t]+$/, "", f4)
    gsub(/^[ \t]+|[ \t]+$/, "", f5)
    if (f2 == "Metric" && f3 == "Threshold" && f4 == "Measured" && f5 == "Result") {
        header++
        if (NF != 6) { print "header row is malformed"; bad = 1 }
        next
    }
    if (f2 != "" && f2 ~ /^:?-+:?$/ && f3 ~ /^:?-+:?$/ && f4 ~ /^:?-+:?$/ && f5 ~ /^:?-+:?$/) {
        separator++
        if (NF != 6) { print "separator row is malformed"; bad = 1 }
        next
    }
    # Any other pipe row — including indented rows, empty-name rows, and
    # rows with the wrong column count — is a data row and must satisfy
    # the acceptance surface exactly.
    rows++
    if (NF != 6) { print "table row has wrong column count: \"" f2 "\""; bad = 1 }
    if (f2 == "") { print "table row with empty metric name"; bad = 1 }
    if (f4 == "") { print "row \"" f2 "\" has an empty Measured cell"; bad = 1 }
    if (f5 != "PASS") { print "row \"" f2 "\" verdict is not an exact PASS"; bad = 1 }
    if (f2 in want) { want[f2]++ } else { print "unexpected metric row \"" f2 "\""; bad = 1 }
}
END {
    if (header != 1) { print "measurement table must have exactly one header row"; exit 1 }
    if (separator != 1) { print "measurement table must have exactly one separator row"; exit 1 }
    if (rows == 0) { print "measurement table has no data rows"; exit 1 }
    for (i = 1; i <= n; i++)
        if (want[req[i]] != 1) { print "required row \"" req[i] "\" not present exactly once"; exit 1 }
    if (bad) exit 1
}' "$EVIDENCE"; then
    echo "release gate: BLOCKED — measurement record incomplete or not all PASS"
    exit 1
fi

echo "release gate: PASS — physical-device performance sign-off recorded on $signoff_date"
