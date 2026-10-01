#!/usr/bin/env bash
# Release gate: physical-device performance sign-off.
#
# Fails closed (exit 1) until docs/performance-device-evidence.md carries a
# dated physical-device measurement. This is a pre-submission gate, not a
# synthetic pass: it blocks release while any sign-off field is PENDING.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EVIDENCE="$REPO_ROOT/docs/performance-device-evidence.md"

if [[ ! -f "$EVIDENCE" ]]; then
    echo "release gate: BLOCKED — evidence file missing: $EVIDENCE"
    exit 1
fi

signoff_date="$(sed -n 's/^<!-- SIGN_OFF_DATE: \([^ ]*\) -->$/\1/p' "$EVIDENCE")"

if [[ -z "$signoff_date" ]]; then
    echo "release gate: BLOCKED — SIGN_OFF_DATE marker missing from $EVIDENCE"
    exit 1
fi

if [[ "$signoff_date" == "PENDING" ]]; then
    echo "release gate: BLOCKED — physical-device performance sign-off is pending owner device run"
    exit 1
fi

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

# The measurement table must still contain its full set of required rows,
# each with an explicit PASS verdict. Deleting or altering rows keeps the
# gate closed; only a complete, dated, all-PASS record passes.
required_rows=(
    "Sustained FPS (full race)"
    "Frame time p95"
    "CPU simulation p95"
    "Render submission p95"
    "GPU p95"
    "Recursive nodes (medium tier)"
    "Geometry/draw-ish nodes (medium tier)"
    "Road chunks (medium tier)"
    "Resident memory"
    "Retry-loop memory growth"
    "Transient allocation"
    "Title-to-race load time"
    "Thermal state"
)
for row in "${required_rows[@]}"; do
    if ! grep -F "| $row |" "$EVIDENCE" | grep -qE 'PASS *\|$'; then
        echo "release gate: BLOCKED — required metric row '$row' is missing or lacks a PASS verdict"
        exit 1
    fi
done

echo "release gate: PASS — physical-device performance sign-off recorded on $signoff_date"
exit 0
