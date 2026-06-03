#!/usr/bin/env bash
# Validate FAA FRQ import and distance-ranked channel API without starting SDR hardware.
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND="${PROJECT_ROOT}/src/backend/rtl_windows_backend.py"
OUT='/c/Users/jim/Downloads'
FRQ_ZIP="${1:-${OUT}/FAA_NASR_2026-05-14_FRQ_CSV.zip}"
REPORT="${OUT}/RTL-Windows-ADS-B-Tracker_Airband_Catalog_API_Test.txt"
LOG="${OUT}/RTL-Windows-ADS-B-Tracker_Airband_Catalog_API_Test.log"
TEST_CATALOG="${OUT}/RTL-Windows-ADS-B-Tracker_Airband_Catalog_API_Test_catalog.json"
TEST_SETTINGS="${OUT}/RTL-Windows-ADS-B-Tracker_Airband_Catalog_API_Test_settings.json"
CHANNELS_JSON="${OUT}/RTL-Windows-ADS-B-Tracker_Airband_Catalog_API_Test_channels.json"
UI_HTML="${OUT}/RTL-Windows-ADS-B-Tracker_Airband_Catalog_API_Test_index.html"
UI_JS="${OUT}/RTL-Windows-ADS-B-Tracker_Airband_Catalog_API_Test_app.js"
API_PORT=19090
DUMP_PORT=19180
BACKEND_PID=''
fail(){ printf 'ERROR: %s\n' "$1" >&2; exit 1; }
stop_backend(){
    if [[ -n "${BACKEND_PID}" ]] && kill -0 "${BACKEND_PID}" 2>/dev/null; then
        kill -INT "${BACKEND_PID}" 2>/dev/null || true
        sleep 1
        kill -KILL "${BACKEND_PID}" 2>/dev/null || true
        wait "${BACKEND_PID}" 2>/dev/null || true
    fi
    BACKEND_PID=''
}
trap stop_backend EXIT
[[ "${MSYSTEM:-}" == "UCRT64" ]] || fail "Run from MSYS2 UCRT64."
for cmd in python3 curl; do command -v "${cmd}" >/dev/null 2>&1 || fail "${cmd} is missing."; done
[[ -s "${FRQ_ZIP}" ]] || fail "FAA FRQ ZIP missing: ${FRQ_ZIP}"
mkdir -p "${OUT}"
rm -f "${REPORT}" "${LOG}" "${TEST_CATALOG}" "${TEST_SETTINGS}" "${CHANNELS_JSON}" "${UI_HTML}" "${UI_JS}"
exec > >(tee "${REPORT}") 2>&1
printf 'RTL-Windows-ADS-B-Tracker FAA airband catalog API test - %s\n' "$(date -Is 2>/dev/null || date)"
python3 "${PROJECT_ROOT}/src/backend/faa_airband_catalog.py" --frq-zip "${FRQ_ZIP}" --output "${TEST_CATALOG}"
python3 - "${TEST_CATALOG}" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
assert d["source"] == "FAA NASR Frequency Data FRQ.csv"
assert "2026/05/14" in d["effective_dates"]
assert d["channel_count"] > 10000
rows=d["channels"]
assert any(r["serviced_facility"]=="1V6" and r["frequency_mhz"]==122.8 and r["frequency_use"]=="CTAF" for r in rows)
assert any(r["serviced_facility"]=="1V6" and r["frequency_mhz"]==120.025 for r in rows)
print("PASS: FAA FRQ import produced normalized civil-airband records including Fremont County examples.")
print("Imported channel count:", d["channel_count"])
PY
python3 "${BACKEND}" --host 127.0.0.1 --port "${API_PORT}" --dump-http-port "${DUMP_PORT}" \
    --settings-file "${TEST_SETTINGS}" --airband-catalog-file "${TEST_CATALOG}" >"${LOG}" 2>&1 &
BACKEND_PID=$!
for attempt in $(seq 1 20); do
    if curl -fsS "http://127.0.0.1:${API_PORT}/api/airband/channels?radius_miles=100&limit=20" >"${CHANNELS_JSON}" 2>/dev/null; then break; fi
    kill -0 "${BACKEND_PID}" 2>/dev/null || break
    sleep 1
done
[[ -s "${CHANNELS_JSON}" ]] || { sed -n '1,160p' "${LOG}" || true; fail "Airband API did not become available."; }
python3 - "${CHANNELS_JSON}" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
assert d["catalog_available"] is True
assert d["receiver_location"]["latitude"] == 38.7467
assert d["matching_channel_count"] > 0
rows=d["channels"]
assert len(rows) <= 20
assert [r["distance_miles"] for r in rows] == sorted(r["distance_miles"] for r in rows)
assert any(r["serviced_facility"]=="1V6" and r["frequency_mhz"]==122.8 for r in rows)
print("PASS: API ranks nearby FAA channels from the Cripple Creek receiver location.")
for row in rows[:8]:
    print(f"  {row['distance_miles']:>5.1f} mi  {row['frequency_mhz']:>7.3f}  {row['frequency_use']:<14} {row['serviced_facility_name']}")
PY
curl -fsS "http://127.0.0.1:${API_PORT}/" >"${UI_HTML}"
curl -fsS "http://127.0.0.1:${API_PORT}/static/app.js" >"${UI_JS}"
grep -q 'id="airband-body"' "${UI_HTML}" || fail "Browser page lacks nearby airband panel."
grep -q '/api/airband/channels' "${UI_JS}" || fail "Browser JavaScript does not request ranked airband channels."
printf 'PASS: Browser UI exposes the read-only nearby FAA channel list.\n'
printf '\nPASS: FAA airband catalog import and distance-ranked API/UI baseline validated without SDR use.\n'
