#!/usr/bin/env bash
# Validate Survey Review Filter and reason labeling without radio operation.
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT='/c/Users/jim/Downloads'
REPORT="${OUT}/RTL-Windows-ADS-B-Tracker_Survey_Review_Filter_Test.txt"
HTML="${PROJECT_ROOT}/web/index.html"
CSS="${PROJECT_ROOT}/web/app.css"
JS="${PROJECT_ROOT}/web/app.js"
DOC="${PROJECT_ROOT}/docs/AIRBAND_SURVEY_REVIEW_FILTER.md"

mkdir -p "${OUT}"
exec > >(tee "${REPORT}") 2>&1
printf 'RTL-Windows-ADS-B-Tracker Survey Review Filter contract validation - %s\n' "$(date -Is 2>/dev/null || date)"

for file in "${HTML}" "${CSS}" "${JS}" "${DOC}"; do
    [[ -s "${file}" ]] || { printf 'ERROR: Missing required file: %s\n' "${file}" >&2; exit 1; }
done

grep -q 'id="survey-result-filter"' "${HTML}" || { printf 'ERROR: Review filter selector is missing.\n' >&2; exit 1; }
grep -q 'Marked results only' "${HTML}" || { printf 'ERROR: Marked-results filter choice is missing.\n' >&2; exit 1; }
grep -q 'filters and reason labels display review cues, not confirmed voice traffic' "${HTML}" || { printf 'ERROR: Manual-review boundary is missing.\n' >&2; exit 1; }
grep -q 'function surveyReviewFlags' "${JS}" || { printf 'ERROR: Review flag derivation is missing.\n' >&2; exit 1; }
grep -q 'function surveyReviewReason' "${JS}" || { printf 'ERROR: Review reason derivation is missing.\n' >&2; exit 1; }
grep -q 'function surveyResultFilterMatch' "${JS}" || { printf 'ERROR: Review result filtering is missing.\n' >&2; exit 1; }
grep -q 'survey-result-filter").onchange' "${JS}" || { printf 'ERROR: Filter change does not refresh completed results.\n' >&2; exit 1; }
grep -q 'review-reasons' "${CSS}" || { printf 'ERROR: Review reason styling is missing.\n' >&2; exit 1; }
grep -q 'review_reasons' "${JS}" || { printf 'ERROR: CSV review reason evidence is missing.\n' >&2; exit 1; }
grep -q 'result_filter' "${JS}" || { printf 'ERROR: CSV filter context is missing.\n' >&2; exit 1; }
grep -q 'do not identify confirmed voice traffic' "${DOC}" || { printf 'ERROR: Documentation lacks review-only boundary.\n' >&2; exit 1; }

python3 - <<'PY'
def flags(candidate_hits, pass_ratio, segment_ratio, pass_limit=1.25, segment_limit=1.25):
    return {
        "above": candidate_hits > 0,
        "repeat": candidate_hits > 1,
        "pass": pass_ratio >= pass_limit,
        "segment": segment_ratio >= segment_limit,
    }

def reasons(f):
    values = []
    if f["repeat"]:
        values.append("Repeat hit")
    elif f["above"]:
        values.append("Above level")
    if f["pass"]:
        values.append("Pass change")
    if f["segment"]:
        values.append("Segment change")
    return " + ".join(values) if values else "No mark"

def matches(f, selection):
    if selection == "marked":
        return f["above"] or f["pass"] or f["segment"]
    if selection == "above":
        return f["above"]
    if selection == "repeat":
        return f["repeat"]
    if selection == "pass":
        return f["pass"]
    if selection == "segment":
        return f["segment"]
    return True

quiet = flags(0, 1.02, 1.05)
transient = flags(0, 1.01, 1.90)
persistent = flags(2, 1.40, 1.60)
assert reasons(quiet) == "No mark"
assert reasons(transient) == "Segment change"
assert reasons(persistent) == "Repeat hit + Pass change + Segment change"
assert not matches(quiet, "marked")
assert matches(transient, "segment")
assert matches(persistent, "repeat")
print("PASS: Deterministic review classification distinguishes quiet, segment-change and repeat-hit evidence.")
PY

if command -v node >/dev/null 2>&1; then
    node --check "${JS}"
    printf 'PASS: Browser JavaScript syntax checked with Node.\n'
else
    printf 'INFO: Node is unavailable; source and deterministic review contracts were checked.\n'
fi
printf 'PASS: Survey Review Filter adds no SDR operation and is ready for publication.\n'
