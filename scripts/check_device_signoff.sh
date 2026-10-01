#!/usr/bin/env bash
# Physical-device performance sign-off gate (issue #37).
#
# Fails CLOSED (non-zero) unless docs/performance-device-evidence.md records a
# complete owner sign-off:
#   * each of the four metadata markers appears exactly once with a
#     non-empty, non-PENDING value;
#   * SIGN_OFF_DATE is a real ISO calendar date (pure bash, no GNU date);
#   * zero PENDING placeholder tokens anywhere in the record;
#   * the measurement table has exactly its header + separator and every
#     required metric row exactly once — no extras, no malformed rows;
#   * each row's Threshold cell matches the checklist budget verbatim;
#   * each Measured cell is a plausible measurement (numeric within the
#     bound, or the allowed verdict vocabulary) for that metric.
#
# Trust model: this gate proves the RECORD is complete, consistent, and
# dated. The authenticity of the underlying device run remains a human
# sign-off accountable via git blame — no text gate can prove a physical
# measurement occurred. The record currently encodes "PENDING — owner
# physical-device run not yet completed", so release readiness stays
# blocked until real measurements are recorded. The gate NEVER synthesizes
# a pass and this script must not be weakened to fake one.
set -euo pipefail

cd "$(dirname "$0")/.."

EVIDENCE="docs/performance-device-evidence.md"

if [[ ! -f "$EVIDENCE" ]]; then
    echo "release gate: BLOCKED — $EVIDENCE not found"
    exit 1
fi

marker_value() {
    local name="$1"
    grep -m1 -oE "<!-- ${name}:[^>]*-->" "$EVIDENCE" \
        | sed -E "s/^<!-- ${name}:[[:space:]]*//; s/[[:space:]]*-->\$//" \
        || true
}

marker_count() {
    local name="$1"
    awk -v pat="<!-- ${name}:" 'index($0, pat) { c += gsub(pat, pat) } END { print c + 0 }' "$EVIDENCE"
}

for marker in SIGN_OFF_DATE DEVICE_MODEL IOS_VERSION BUILD_COMMIT; do
    count="$(marker_count "$marker")"
    if [[ "$count" -ne 1 ]]; then
        echo "release gate: BLOCKED — $marker marker must appear exactly once (found $count)"
        exit 1
    fi
    value="$(marker_value "$marker")"
    if [[ -z "$value" ]]; then
        echo "release gate: BLOCKED — $marker marker is empty"
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

if ! awk -F'|' '
function unitnum(v,  t) {
    t = v
    gsub(/[[:space:]]+/, " ", t)
    sub(/ ?fps$/, "", t)
    sub(/ ?ms\/frame$/, "", t)
    sub(/ ?ms$/, "", t)
    sub(/ ?MB\/s$/, "", t)
    sub(/ ?MB$/, "", t)
    sub(/ ?s$/, "", t)
    gsub(/ /, "", t)
    if (t !~ /^[0-9]+(\.[0-9]+)?$/) return -1
    return t + 0
}
BEGIN {
    count = 0
    add("Sustained FPS (full race)", ">= 55", "num", 55, "", 1, 1)
    add("Frame time p95", "<= 16.67 ms", "num", "", 16.67, 1, 1)
    add("CPU simulation p95", "<= 2 ms/frame", "num", "", 2, 1, 1)
    add("Render submission p95", "<= 5 ms/frame", "num", "", 5, 1, 1)
    add("GPU p95", "<= 8 ms/frame", "num", "", 8, 1, 1)
    add("Recursive nodes (medium tier)", "<= 650", "num", "", 650, 1, 1)
    add("Geometry/draw-ish nodes (medium tier)", "<= 420", "num", "", 420, 1, 1)
    add("Road chunks (medium tier)", "14", "num", 14, 14, 1, 1)
    add("Resident memory", "< 650 MB", "num", "", 650, 0, 1)
    add("Transient allocation", "< 5 MB/s", "num", "", 5, 0, 1)
    add("Title-to-race load time", "< 3 s", "num", "", 3, 0, 1)
    add("Retry-loop memory growth", "no sustained growth", "word", "", "", 0, 0)
    words["Retry-loop memory growth"] = "|none|stable|no growth|no sustained growth|"
    add("Thermal state", "<= `.fair`", "word", "", "", 0, 0)
    words["Thermal state"] = "|nominal|fair|"
}
function add(name, threshold, kind, lo, hi, loinc, hinc) {
    order[++count] = name
    want[name] = 0
    th[name] = threshold
    k[name] = kind
    low[name] = lo
    high[name] = hi
    lowInc[name] = loinc
    highInc[name] = hinc
}
function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
{ sub(/\r$/, "") }
/^[ \t]*\|/ {
    f2 = trim($2); f3 = trim($3); f4 = trim($4); f5 = trim($5)
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
    # Any other pipe row (indented, empty-named, wrong-width) is a data row
    # and must satisfy the acceptance surface exactly.
    rows++
    if (NF != 6) { print "table row has wrong column count: \"" f2 "\""; bad = 1 }
    if (f2 == "") { print "table row with empty metric name"; bad = 1 }
    if (f5 != "PASS") { print "row \"" f2 "\" verdict is not an exact PASS"; bad = 1 }
    if (!(f2 in want)) { print "unexpected metric row \"" f2 "\""; bad = 1; next }
    want[f2]++
    if (f3 != th[f2]) { print "row \"" f2 "\" threshold \"" f3 "\" does not match the checklist budget \"" th[f2] "\""; bad = 1 }
    if (f4 == "") { print "row \"" f2 "\" has an empty Measured cell"; bad = 1 }
    else if (k[f2] == "num") {
        v = unitnum(f4)
        if (v < 0) { print "row \"" f2 "\" measured value \"" f4 "\" is not a numeric measurement"; bad = 1 }
        else {
            if (low[f2] != "" && (v < low[f2] || (v == low[f2] && !lowInc[f2]))) {
                print "row \"" f2 "\" measured \"" f4 "\" violates its budget"; bad = 1
            }
            if (high[f2] != "" && (v > high[f2] || (v == high[f2] && !highInc[f2]))) {
                print "row \"" f2 "\" measured \"" f4 "\" violates its budget"; bad = 1
            }
        }
    }
    else if (k[f2] == "word") {
        w = tolower(f4)
        if (index(words[f2], "|" w "|") == 0) {
            print "row \"" f2 "\" measured \"" f4 "\" is outside the allowed verdict vocabulary"; bad = 1
        }
    }
}
END {
    if (header != 1) { print "measurement table must have exactly one header row"; exit 1 }
    if (separator != 1) { print "measurement table must have exactly one separator row"; exit 1 }
    if (rows == 0) { print "measurement table has no data rows"; exit 1 }
    for (i = 1; i <= count; i++)
        if (want[order[i]] != 1) { print "required row \"" order[i] "\" not present exactly once"; exit 1 }
    if (bad) exit 1
}' "$EVIDENCE"; then
    echo "release gate: BLOCKED — measurement record incomplete or not all PASS"
    exit 1
fi

echo "release gate: PASS — physical-device performance sign-off recorded on $signoff_date"
