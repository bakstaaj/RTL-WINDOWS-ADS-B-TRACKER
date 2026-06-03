#!/usr/bin/env bash
# Validate persisted receiver location using an isolated Downloads-side test settings file.
# Intended environment: MSYS2 UCRT64.

set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND="${PROJECT_ROOT}/src/backend/rtl_windows_backend.py"
OUT='/c/Users/jim/Downloads'
REPORT="${OUT}/RTL-Windows-ADS-B-Tracker_Receiver_Location_API_Test.txt"
LOG="${OUT}/RTL-Windows-ADS-B-Tracker_Receiver_Location_API_Test.log"
TEST_SETTINGS="${OUT}/RTL-Windows-ADS-B-Tracker_Receiver_Location_API_Test_settings.json"
STATUS_JSON="${OUT}/RTL-Windows-ADS-B-Tracker_Receiver_Location_API_Test_status.json"
POST_JSON="${OUT}/RTL-Windows-ADS-B-Tracker_Receiver_Location_API_Test_post.json"
UI_HTML="${OUT}/RTL-Windows-ADS-B-Tracker_Receiver_Location_API_Test_index.html"
UI_JS="${OUT}/RTL-Windows-ADS-B-Tracker_Receiver_Location_API_Test_app.js"
API_PORT=18890
DUMP_PORT=18980
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
[[ -s "${BACKEND}" ]] || fail "Backend source is missing."
mkdir -p "${OUT}"
rm -f "${REPORT}" "${LOG}" "${TEST_SETTINGS}" "${STATUS_JSON}" "${POST_JSON}" "${UI_HTML}" "${UI_JS}"
exec > >(tee "${REPORT}") 2>&1

start_backend(){
    python3 "${BACKEND}" --host 127.0.0.1 --port "${API_PORT}" --dump-http-port "${DUMP_PORT}" \
        --settings-file "${TEST_SETTINGS}" >"${LOG}" 2>&1 &
    BACKEND_PID=$!
    for attempt in $(seq 1 20); do
        if curl -fsS "http://127.0.0.1:${API_PORT}/api/status" >"${STATUS_JSON}" 2>/dev/null; then return 0; fi
        kill -0 "${BACKEND_PID}" 2>/dev/null || break
        sleep 1
    done
    sed -n '1,140p' "${LOG}" || true
    fail "Backend did not start for settings validation."
}

printf 'RTL-Windows-ADS-B-Tracker receiver location API test - %s\n' "$(date -Is 2>/dev/null || date)"
printf 'Isolated test settings file: %s\n' "${TEST_SETTINGS}"

start_backend
python3 - "${STATUS_JSON}" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
loc=d["receiver_location"]
assert loc["latitude"] == 38.7467 and loc["longitude"] == -105.1783
print("PASS: Empty settings file starts with the development default receiver location.", loc)
PY

curl -fsS -X POST "http://127.0.0.1:${API_PORT}/api/settings/receiver-location" \
    -H 'Content-Type: application/json' \
    -d '{"label":"Distance Test Receiver","latitude":38.812345,"longitude":-105.245678}' >"${POST_JSON}"
python3 - "${POST_JSON}" "${TEST_SETTINGS}" <<'PY'
import json,sys
reply=json.load(open(sys.argv[1],encoding="utf-8"))
stored=json.load(open(sys.argv[2],encoding="utf-8"))
assert reply["ok"] is True
assert reply["receiver_location"]["label"] == "Distance Test Receiver"
assert stored["receiver_location"]["latitude"] == 38.812345
assert stored["receiver_location"]["longitude"] == -105.245678
print("PASS: Receiver location POST validated values and wrote isolated persistent settings.")
PY

curl -fsS "http://127.0.0.1:${API_PORT}/api/status" >"${STATUS_JSON}"
python3 - "${STATUS_JSON}" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
assert d["receiver_location"]["label"] == "Distance Test Receiver"
assert d["receiver_location"]["latitude"] == 38.812345
print("PASS: Status immediately exposes the saved receiver location for map/airband use.")
PY

curl -fsS "http://127.0.0.1:${API_PORT}/" >"${UI_HTML}"
curl -fsS "http://127.0.0.1:${API_PORT}/static/app.js" >"${UI_JS}"
grep -q 'id="save-location"' "${UI_HTML}" || fail "Served UI lacks receiver-location Save control."
grep -q '/api/settings/receiver-location' "${UI_JS}" || fail "Served UI does not call receiver-location API."
printf 'PASS: Browser assets include receiver-location controls and API integration.\n'

stop_backend
rm -f "${STATUS_JSON}"
start_backend
curl -fsS "http://127.0.0.1:${API_PORT}/api/status" >"${STATUS_JSON}"
python3 - "${STATUS_JSON}" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
loc=d["receiver_location"]
assert loc["label"] == "Distance Test Receiver"
assert loc["latitude"] == 38.812345 and loc["longitude"] == -105.245678
print("PASS: Receiver location persists across a backend restart.", loc)
PY

printf '\nPASS: Persisted receiver-location API/UI baseline is validated using isolated test settings.\n'
printf 'Report saved to: C:\\Users\\jim\\Downloads\\RTL-Windows-ADS-B-Tracker_Receiver_Location_API_Test.txt\n'
