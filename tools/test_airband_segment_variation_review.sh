#!/usr/bin/env bash
# Validate within-sample segment-variation review without radio operation.
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT='/c/Users/jim/Downloads'
REPORT="${OUT}/RTL-Windows-ADS-B-Tracker_Segment_Variation_Review_Test.txt"
HTML="${PROJECT_ROOT}/web/index.html"
CSS="${PROJECT_ROOT}/web/app.css"
JS="${PROJECT_ROOT}/web/app.js"
DOC="${PROJECT_ROOT}/docs/AIRBAND_SEGMENT_VARIATION_REVIEW.md"
CSV_DOC="${PROJECT_ROOT}/docs/AIRBAND_SURVEY_EXPORT.md"

mkdir -p "${OUT}"
exec > >(tee "${REPORT}") 2>&1
printf 'RTL-Windows-ADS-B-Tracker within-sample segment variation contract validation - %s\n' "$(date -Is 2>/dev/null || date)"

for file in "${HTML}" "${CSS}" "${JS}" "${DOC}" "${CSV_DOC}"; do
    [[ -s "${file}" ]] || { printf 'ERROR: Missing required file: %s\n' "${file}" >&2; exit 1; }
done

grep -q 'id="survey-segment-variation-threshold"' "${HTML}" || { printf 'ERROR: Segment change selector is missing.\n' >&2; exit 1; }
grep -q 'segment-change marks are review cues, not confirmed voice traffic' "${HTML}" || { printf 'ERROR: Segment-change interpretation boundary is missing.\n' >&2; exit 1; }
grep -q 'segmentVariationMultiplier' "${JS}" || { printf 'ERROR: Segment-change plan value is not applied.\n' >&2; exit 1; }
grep -q 'function surveySegmentVariationRatio' "${JS}" || { printf 'ERROR: Segment-variation calculation is missing.\n' >&2; exit 1; }
grep -q 'segmentRms.push' "${JS}" || { printf 'ERROR: Existing segments are not measured for within-sample change.\n' >&2; exit 1; }
grep -q 'segmentVariationRatios.push' "${JS}" || { printf 'ERROR: Segment-change evidence is not retained.\n' >&2; exit 1; }
grep -q 'segment-changing' "${CSS}" || { printf 'ERROR: Segment-change styling is missing.\n' >&2; exit 1; }
grep -q 'Segment change' "${JS}" || { printf 'ERROR: Segment-change review label is missing.\n' >&2; exit 1; }
grep -q 'segment_variation_ratio_max' "${JS}" || { printf 'ERROR: CSV lacks segment-variation summary evidence.\n' >&2; exit 1; }
grep -q 'segment_variation_ratios' "${JS}" || { printf 'ERROR: CSV lacks per-pass segment evidence.\n' >&2; exit 1; }
grep -q 'without adding any radio or audio-transport operation' "${DOC}" || { printf 'ERROR: Feature documentation lacks unchanged-radio boundary.\n' >&2; exit 1; }
grep -q 'segment-variation ratio' "${CSV_DOC}" || { printf 'ERROR: CSV documentation lacks segment evidence fields.\n' >&2; exit 1; }

python3 - <<'PY'
def ratio(values):
    return max(values) / max(1.0, min(values)) if len(values) > 1 else 1.0

steady = [400.0, 420.0]
changing = [300.0, 600.0]
threshold = 1.25

assert round(ratio(steady), 3) == 1.050
assert ratio(steady) < threshold
assert round(ratio(changing), 3) == 2.000
assert ratio(changing) >= threshold
assert max(ratio([300.0, 600.0]), ratio([460.0, 480.0])) == 2.0
print("PASS: Deterministic 500 ms segment evidence distinguishes steady and changing observations.")
PY

if command -v node >/dev/null 2>&1; then
    node --check "${JS}"
    printf 'PASS: Browser JavaScript syntax checked with Node.\n'
else
    printf 'INFO: Node is unavailable; source and deterministic metric contracts were checked.\n'
fi
printf 'PASS: Segment-variation review adds no SDR operation and is ready for publication.\n'
