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

if ! [[ "$signoff_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "release gate: BLOCKED — SIGN_OFF_DATE '$signoff_date' is not an ISO date (YYYY-MM-DD)"
    exit 1
fi

pending_cells="$(grep -c 'PENDING' "$EVIDENCE" || true)"
if [[ "$pending_cells" -ne 0 ]]; then
    echo "release gate: BLOCKED — $pending_cells sign-off field(s) still PENDING"
    exit 1
fi

echo "release gate: PASS — physical-device performance sign-off recorded on $signoff_date"
exit 0
