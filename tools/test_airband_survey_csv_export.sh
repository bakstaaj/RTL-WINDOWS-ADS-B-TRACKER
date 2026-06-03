#!/usr/bin/env bash
# Validate completed Survey CSV export as browser-only presentation/export behavior.
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT='/c/Users/jim/Downloads'
REPORT="${OUT}/RTL-Windows-ADS-B-Tracker_Survey_CSV_Export_Test.txt"
HTML="${PROJECT_ROOT}/web/index.html"
JS="${PROJECT_ROOT}/web/app.js"
DOC="${PROJECT_ROOT}/docs/AIRBAND_SURVEY_EXPORT.md"

mkdir -p "${OUT}"
exec > >(tee "${REPORT}") 2>&1
printf 'RTL-Windows-ADS-B-Tracker Survey CSV export contract validation - %s\n' "$(date -Is 2>/dev/null || date)"
[[ -s "${HTML}" && -s "${JS}" && -s "${DOC}" ]] || { printf 'ERROR: Survey CSV export source/documentation is missing.\n' >&2; exit 1; }

grep -q 'id="export-airband-survey"' "${HTML}" || { printf 'ERROR: Export Survey CSV button is missing.\n' >&2; exit 1; }
grep -q 'Export Survey CSV for manual review' "${HTML}" || { printf 'ERROR: Browser help does not describe manual-review export.\n' >&2; exit 1; }
grep -q 'function exportAirbandSurveyCsv' "${JS}" || { printf 'ERROR: Browser export function is missing.\n' >&2; exit 1; }
grep -q 'function surveyCsvField' "${JS}" || { printf 'ERROR: CSV field encoding is missing.\n' >&2; exit 1; }
grep -q 'frequency_mhz' "${JS}" || { printf 'ERROR: Frequency field is not included in CSV source contract.\n' >&2; exit 1; }
grep -q 'candidate_hits' "${JS}" || { printf 'ERROR: Candidate hit field is not included in CSV source contract.\n' >&2; exit 1; }
grep -q 'pass_variation_ratio' "${JS}" || { printf 'ERROR: Pass variation ratio field is not included in CSV source contract.\n' >&2; exit 1; }
grep -q 'segment_variation_ratio_max' "${JS}" || { printf 'ERROR: Segment variation ratio field is not included in CSV source contract.\n' >&2; exit 1; }
grep -q 'pass_rms_values' "${JS}" || { printf 'ERROR: Per-pass level field is not included in CSV source contract.\n' >&2; exit 1; }
grep -q 'segment_variation_ratios' "${JS}" || { printf 'ERROR: Per-pass segment variation fields are not included in CSV source contract.\n' >&2; exit 1; }
grep -q 'export-airband-survey").disabled=running||!airbandSurvey.results.length' "${JS}" || { printf 'ERROR: Export enablement is not gated by completed results.\n' >&2; exit 1; }
grep -q 'exportAirbandSurveyCsv()' "${JS}" || { printf 'ERROR: Export button action is not registered.\n' >&2; exit 1; }
grep -q 'does not retune a receiver, request audio, play audio' "${DOC}" || { printf 'ERROR: Export documentation lacks unchanged-radio boundary.\n' >&2; exit 1; }

if command -v node >/dev/null 2>&1; then
    node --check "${JS}"
    printf 'PASS: Browser JavaScript syntax checked with Node.\n'
else
    printf 'INFO: Node is unavailable; export markers and boundary documentation were checked.\n'
fi

printf 'PASS: Completed Survey CSV export UI/output contract is present.\n'
printf 'PASS: No SDR hardware validation is required because this feature changes only export of completed browser measurements.\n'
