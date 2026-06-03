#!/usr/bin/env bash
# Import an official FAA NASR FRQ CSV ZIP into excluded application runtime data.
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_FRQ_ZIP='/c/Users/jim/Downloads/FAA_NASR_2026-05-14_FRQ_CSV.zip'
FRQ_ZIP="${1:-${DEFAULT_FRQ_ZIP}}"
OUTPUT="${2:-${PROJECT_ROOT}/runtime/settings/faa_airband_catalog.json}"
[[ -s "${FRQ_ZIP}" ]] || { printf 'ERROR: FAA FRQ ZIP not found: %s\n' "${FRQ_ZIP}" >&2; exit 1; }
python3 "${PROJECT_ROOT}/src/backend/faa_airband_catalog.py" --frq-zip "${FRQ_ZIP}" --output "${OUTPUT}"
printf 'Imported FAA FRQ catalog to: %s\n' "${OUTPUT}"
